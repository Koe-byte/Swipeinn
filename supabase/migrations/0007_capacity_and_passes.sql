-- Listing capacity, private passes and owner rejection.
--
-- Three product rules drive this migration:
--
--   1. A listing says how many people it can accommodate.
--   2. A left swipe ("pass") is private to the renter. ADR 0003 keeps left and
--      right swipes actor-private; only a right swipe (like) is mirrored into
--      the owner's review queue. Passes therefore get their own requester-only
--      table instead of reusing listing_likes.
--   3. An owner can reject a pending like. The row stays so the renter's
--      Discover hides the card and the decision can be undone without losing
--      history.
--
-- Safe to re-run. Apply after 0001-0006.

begin;

-- ---------------------------------------------------------------------------
-- Listings: capacity
-- ---------------------------------------------------------------------------

alter table public.listings
  add column if not exists "capacity" integer not null default 1;

-- ---------------------------------------------------------------------------
-- Listing passes: private "not for me" decisions
--
-- The document id is deterministic ("${listingId}_${requesterUid}") so the
-- client can address it like any other single-key row. The owner has no read
-- policy here: a pass must never reach the review queue.
-- ---------------------------------------------------------------------------

create table if not exists public.listing_passes (
  "id"           text primary key,
  "listingId"    text not null references public.listings ("id") on delete cascade,
  "requesterUid" uuid not null references auth.users (id) on delete cascade,
  "passedAt"     bigint not null default 0
);

create unique index if not exists listing_passes_listing_requester_idx
  on public.listing_passes ("listingId", "requesterUid");
create index if not exists listing_passes_requester_idx
  on public.listing_passes ("requesterUid");

alter table public.listing_passes enable row level security;

drop policy if exists "passes_select_own" on public.listing_passes;
create policy "passes_select_own" on public.listing_passes
  for select to authenticated
  using ("requesterUid" = (select auth.uid()));

drop policy if exists "passes_insert_own" on public.listing_passes;
create policy "passes_insert_own" on public.listing_passes
  for insert to authenticated
  with check (
    public.is_verified()
    and "requesterUid" = (select auth.uid())
    and exists (
      select 1
      from public.listings l
      where l."id" = "listingId"
        and l."deletedAt" is null
        and l."ownerUid" <> (select auth.uid())
    )
  );

-- Undo deletes the pass. There is no update policy on purpose.
drop policy if exists "passes_delete_own" on public.listing_passes;
create policy "passes_delete_own" on public.listing_passes
  for delete to authenticated
  using ("requesterUid" = (select auth.uid()));

revoke all on public.listing_passes from anon;
grant select, insert, delete on public.listing_passes to authenticated;

-- ---------------------------------------------------------------------------
-- Likes: the owner may approve / reject / reopen
--
-- 0002 only allowed the owner to land on 'approved'. Rejection and its undo
-- need the other states too. Identity fields stay frozen by
-- listing_likes_freeze_identity.
-- ---------------------------------------------------------------------------

drop policy if exists "likes_update_owner_approves" on public.listing_likes;
drop policy if exists "likes_update_owner_decides" on public.listing_likes;
create policy "likes_update_owner_decides" on public.listing_likes
  for update to authenticated
  using (
    public.is_verified()
    and exists (
      select 1
      from public.listings l
      where l."id" = "listingId"
        and l."ownerUid" = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.listings l
      where l."id" = "listingId"
        and l."ownerUid" = (select auth.uid())
    )
    and "status" in ('pending', 'approved', 'rejected')
  );

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

alter table public.listing_passes replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.listing_passes;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end;
$$;

commit;
