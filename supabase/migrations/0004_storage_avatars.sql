-- Storage repair + avatar bucket.
--
-- Why this file exists: `0003_storage_realtime.sql` creates the listing-photos
-- bucket and its policies in one transaction. A project that has the bucket but
-- not the policies accepts no uploads at all and answers every attempt with
--
--   403 new row violates row-level security policy
--
-- which is what the app shows after "Publish Listing Card" with photos. This
-- file is self-contained and idempotent, so running it repairs that state no
-- matter which half of 0003 landed.
--
-- It also adds the `avatars` bucket for profile pictures:
--
--   users/{uid}/avatar_<timestamp>.jpg
--
-- Both buckets are public for reads (the app stores plain URLs in Postgres),
-- and writes are restricted to the uploader's own `users/{uid}/...` folder.

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'listing-photos',
    'listing-photos',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/gif']
  ),
  (
    'avatars',
    'avatars',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/gif']
  )
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- storage.foldername('users/<uid>/listings/<listingId>/file.jpg')
--   = {users,<uid>,listings,<listingId>}
-- storage.foldername('users/<uid>/avatar.jpg')
--   = {users,<uid>}
--
-- So the uploader's uid is always element 2 and element 1 is the literal
-- `users`. Getting this wrong is silent: every upload is rejected by RLS.
--
-- The size and MIME checks live on the bucket itself (`file_size_limit`,
-- `allowed_mime_types`). They are deliberately NOT repeated in the policies:
-- if Storage omits a metadata key the policy would reject a legitimate upload
-- for no reason.

-- ---------------------------------------------------------------------------
-- listing-photos
-- ---------------------------------------------------------------------------

drop policy if exists "listing_photos_read" on storage.objects;
create policy "listing_photos_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'listing-photos');

drop policy if exists "listing_photos_insert_own" on storage.objects;
create policy "listing_photos_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );

drop policy if exists "listing_photos_update_own" on storage.objects;
create policy "listing_photos_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );

drop policy if exists "listing_photos_delete_own" on storage.objects;
create policy "listing_photos_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );

-- ---------------------------------------------------------------------------
-- avatars
-- ---------------------------------------------------------------------------

drop policy if exists "avatars_read" on storage.objects;
create policy "avatars_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );

commit;
