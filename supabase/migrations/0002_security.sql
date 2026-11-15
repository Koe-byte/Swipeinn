-- Swipeinn security model.
--
-- This is a straight port of firestore.rules. The rules that mattered there and
-- must still hold here:
--
--   1. users/{uid} is private to that account.
--   2. Any signed-in account can read listings; only the owner can write one.
--   3. Only the listing owner can read the likes queue.
--   4. Only the listing owner can open a match, and only from a like that
--      already exists.
--   5. Only match participants can read a conversation, and the sender must be
--      the writer.
--   6. A message may only change its structured viewing-proposal fields.
--
-- Everything is default-deny: RLS is enabled on every table and a table with no
-- matching policy returns no rows.

begin;

-- Firestore read email_verified straight off the ID token. Supabase's JWT has no
-- such claim, so the equivalent check reads auth.users instead. It has to be
-- security definer: the caller is `authenticated`, which cannot see auth.users.
create or replace function public.is_verified()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users u
    where u.id = (select auth.uid())
      and u.email_confirmed_at is not null
  );
$$;

revoke all on function public.is_verified() from public;
grant execute on function public.is_verified() to authenticated;

-- ---------------------------------------------------------------------------
-- Users: one private profile per account.
-- ---------------------------------------------------------------------------

alter table public.users enable row level security;

drop policy if exists "users_select_own" on public.users;
create policy "users_select_own" on public.users
  for select to authenticated
  using ("uid" = (select auth.uid()));

drop policy if exists "users_insert_own" on public.users;
create policy "users_insert_own" on public.users
  for insert to authenticated
  with check ("uid" = (select auth.uid()));

drop policy if exists "users_update_own" on public.users;
create policy "users_update_own" on public.users
  for update to authenticated
  using ("uid" = (select auth.uid()))
  with check ("uid" = (select auth.uid()));

-- No delete policy: profile rows disappear only with the auth user.

-- ---------------------------------------------------------------------------
-- Listings: readable by any signed-in account, writable by the verified owner.
-- ---------------------------------------------------------------------------

alter table public.listings enable row level security;

drop policy if exists "listings_select_signed_in" on public.listings;
create policy "listings_select_signed_in" on public.listings
  for select to authenticated
  using (true);

drop policy if exists "listings_insert_own_verified" on public.listings;
create policy "listings_insert_own_verified" on public.listings
  for insert to authenticated
  with check (public.is_verified() and "ownerUid" = (select auth.uid()));

drop policy if exists "listings_update_own_verified" on public.listings;
create policy "listings_update_own_verified" on public.listings
  for update to authenticated
  using (public.is_verified() and "ownerUid" = (select auth.uid()))
  with check (public.is_verified() and "ownerUid" = (select auth.uid()));

drop policy if exists "listings_delete_own_verified" on public.listings;
create policy "listings_delete_own_verified" on public.listings
  for delete to authenticated
  using (public.is_verified() and "ownerUid" = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Likes: the requester sees their own row, the owner sees the whole queue.
-- ---------------------------------------------------------------------------

alter table public.listing_likes enable row level security;

drop policy if exists "likes_select_requester_or_owner" on public.listing_likes;
create policy "likes_select_requester_or_owner" on public.listing_likes
  for select to authenticated
  using (
    "requesterUid" = (select auth.uid())
    or exists (
      select 1
      from public.listings l
      where l."id" = "listingId"
        and l."ownerUid" = (select auth.uid())
    )
  );

drop policy if exists "likes_insert_self_pending" on public.listing_likes;
create policy "likes_insert_self_pending" on public.listing_likes
  for insert to authenticated
  with check (
    public.is_verified()
    and "requesterUid" = (select auth.uid())
    and "status" = 'pending'
  );

drop policy if exists "likes_update_owner_approves" on public.listing_likes;
create policy "likes_update_owner_approves" on public.listing_likes
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
    and "status" = 'approved'
  );

drop policy if exists "likes_delete_requester_or_owner" on public.listing_likes;
create policy "likes_delete_requester_or_owner" on public.listing_likes
  for delete to authenticated
  using (
    public.is_verified()
    and (
      "requesterUid" = (select auth.uid())
      or exists (
        select 1
        from public.listings l
        where l."id" = "listingId"
          and l."ownerUid" = (select auth.uid())
      )
    )
  );

-- ---------------------------------------------------------------------------
-- Matches: participants only, created by the listing owner from a real like.
-- ---------------------------------------------------------------------------

alter table public.matches enable row level security;

drop policy if exists "matches_select_participant" on public.matches;
create policy "matches_select_participant" on public.matches
  for select to authenticated
  using ((select auth.uid()) = any ("participantUids"));

drop policy if exists "matches_insert_owner_from_like" on public.matches;
create policy "matches_insert_owner_from_like" on public.matches
  for insert to authenticated
  with check (
    public.is_verified()
    and "ownerUid" = (select auth.uid())
    and "requesterUid" <> (select auth.uid())
    and cardinality("participantUids") = 2
    and (select auth.uid()) = any ("participantUids")
    and "requesterUid" = any ("participantUids")
    and "ownerUid" = (
      select l."ownerUid" from public.listings l where l."id" = "listingId"
    )
    and exists (
      select 1
      from public.listing_likes ll
      where ll."listingId" = "listingId"
        and ll."requesterUid" = "requesterUid"
    )
  );

drop policy if exists "matches_update_participant" on public.matches;
create policy "matches_update_participant" on public.matches
  for update to authenticated
  using ((select auth.uid()) = any ("participantUids"))
  with check ((select auth.uid()) = any ("participantUids"));

-- No delete policy: closing a match is a status change, not a delete.

-- RLS cannot express "these columns are immutable" on an UPDATE, because a
-- WITH CHECK clause only sees the new row. Firestore did it with
-- affectedKeys().hasOnly([...]). A trigger is the direct equivalent: without it
-- a participant could add a third uid to participantUids and hand a stranger
-- read access to the conversation.
create or replace function public.freeze_match_participants()
returns trigger
language plpgsql
as $$
begin
  if new."listingId" <> old."listingId"
     or new."ownerUid" <> old."ownerUid"
     or new."requesterUid" <> old."requesterUid"
     or new."participantUids" <> old."participantUids" then
    raise exception 'Match participants and listing are immutable'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists matches_freeze_participants on public.matches;
create trigger matches_freeze_participants
  before update on public.matches
  for each row execute function public.freeze_match_participants();

-- ---------------------------------------------------------------------------
-- Messages: participants only; message text and sender are immutable.
-- ---------------------------------------------------------------------------

alter table public.messages enable row level security;

drop policy if exists "messages_select_participant" on public.messages;
create policy "messages_select_participant" on public.messages
  for select to authenticated
  using (
    exists (
      select 1
      from public.matches m
      where m."id" = "matchId"
        and (select auth.uid()) = any (m."participantUids")
    )
  );

drop policy if exists "messages_insert_sender" on public.messages;
create policy "messages_insert_sender" on public.messages
  for insert to authenticated
  with check (
    public.is_verified()
    and "senderUid" = (select auth.uid())
    and exists (
      select 1
      from public.matches m
      where m."id" = "matchId"
        and (select auth.uid()) = any (m."participantUids")
    )
  );

drop policy if exists "messages_update_participant" on public.messages;
create policy "messages_update_participant" on public.messages
  for update to authenticated
  using (
    exists (
      select 1
      from public.matches m
      where m."id" = "matchId"
        and (select auth.uid()) = any (m."participantUids")
    )
  )
  with check (
    exists (
      select 1
      from public.matches m
      where m."id" = "matchId"
        and (select auth.uid()) = any (m."participantUids")
    )
  );

-- No delete policy.

-- A message's content is immutable. Firestore said this with
-- affectedKeys().hasOnly(['proposalStatus', 'viewingDate']); here it is a
-- trigger because the client writes a message row through a merge (UPDATE, then
-- INSERT when absent), and Postgres checks column grants on the UPDATE even
-- when it matches zero rows.
create or replace function public.freeze_message_identity()
returns trigger
language plpgsql
as $$
begin
  if new."id" <> old."id"
     or new."matchId" <> old."matchId"
     or new."senderUid" <> old."senderUid"
     or new."text" <> old."text"
     or new."type" <> old."type"
     or new."sentAt" <> old."sentAt" then
    raise exception 'Message content and sender are immutable'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_freeze_identity on public.messages;
create trigger messages_freeze_identity
  before update on public.messages
  for each row execute function public.freeze_message_identity();

-- ---------------------------------------------------------------------------
-- Grants
--
-- Postgres checks table/column privileges before RLS, so a policy alone is not
-- enough. Policies above are scoped to `authenticated`; `anon` gets nothing.
-- ---------------------------------------------------------------------------

revoke all on public.users         from anon;
revoke all on public.listings      from anon;
revoke all on public.listing_likes from anon;
revoke all on public.matches       from anon;
revoke all on public.messages      from anon;

grant select, insert, update, delete on public.users         to authenticated;
grant select, insert, update, delete on public.listings      to authenticated;
grant select, insert, update, delete on public.listing_likes to authenticated;
grant select, insert, update, delete on public.matches       to authenticated;
grant select, insert, update, delete on public.messages      to authenticated;

-- Column-level grants replace Firestore's affectedKeys() rule for likes: an
-- owner may only write the approval fields of a request.
revoke update on public.listing_likes from authenticated;
grant update ("status", "approvedAt") on public.listing_likes to authenticated;

-- Messages keep a full UPDATE grant because the client merges a whole row on
-- send; freeze_message_identity() above is what makes content immutable.

commit;
