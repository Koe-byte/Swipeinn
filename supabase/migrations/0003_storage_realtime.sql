-- Swipeinn storage bucket and realtime publication.
--
-- This replaces storage.rules. The path convention is deliberately identical to
-- the old Firebase Storage layout so a future move is a path-preserving swap:
--
--   users/{uid}/listings/{listingId}/{fileName}
--
-- The listing itself is still guarded by the listings policies; storage can only
-- see the path. Uploaders write into their own folder, only images, max 5 MB.

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'listing-photos',
  'listing-photos',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/gif']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- The bucket is public, so image bytes are readable through the public URL
-- without a policy. This policy only covers the authenticated API path
-- (listing/overwriting), which the app does not use but the dashboard does.
drop policy if exists "listing_photos_read" on storage.objects;
create policy "listing_photos_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'listing-photos');

-- storage.foldername('users/<uid>/listings/<listingId>/file.jpg')
--   = {users,<uid>,listings,<listingId>}
-- so the uploader's uid is element 2, not element 1. Getting this wrong is
-- silent: every upload is rejected by RLS.
drop policy if exists "listing_photos_insert_own" on storage.objects;
create policy "listing_photos_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and (storage.foldername(name))[1] = 'users'
    and (metadata ->> 'size')::bigint <= 5242880
    and (metadata ->> 'mimetype') like 'image/%'
  );

-- Required for overwrite/upsert of an existing object in the same folder.
drop policy if exists "listing_photos_update_own" on storage.objects;
create policy "listing_photos_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and (metadata ->> 'mimetype') like 'image/%'
  );

drop policy if exists "listing_photos_delete_own" on storage.objects;
create policy "listing_photos_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );

-- ---------------------------------------------------------------------------
-- Realtime
--
-- The Dart client's .stream() subscribes to postgres_changes. Without the
-- publication entry it returns the initial rows and then never updates, which
-- looks like a broken listener rather than a missing grant.
--
-- replica identity full is required for Realtime to evaluate RLS policies on
-- UPDATE/DELETE payloads; with the default identity Postgres only ships the
-- primary key and the policy cannot be checked.
-- ---------------------------------------------------------------------------

alter table public.users         replica identity full;
alter table public.listings      replica identity full;
alter table public.listing_likes replica identity full;
alter table public.matches       replica identity full;
alter table public.messages      replica identity full;

do $$
declare
  target text;
begin
  foreach target in array array['users', 'listings', 'listing_likes', 'matches', 'messages']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', target);
    exception
      when duplicate_object then null;
      when undefined_object then null;
    end;
  end loop;
end;
$$;

commit;
