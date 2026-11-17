-- Chat reliability, proposal responses, atomic interest approval, and
-- soft-deleted listings.
--
-- Three problems motivated this migration:
--
--   1. Accepting a viewing proposal used to write the message and the match in
--      two separate requests. One could succeed while the other failed, so the
--      bubble and the banner disagreed.
--   2. Approving interest used to create the match and close the like in two
--      separate requests, which could leave an approved like with no chat.
--   3. Deleting a listing cascaded through matches and messages, so an owner
--      deleting a place erased every conversation about it.
--
-- Everything here is safe to re-run. Apply after 0001-0005.

begin;

-- ---------------------------------------------------------------------------
-- Listings: soft delete
--
-- A deleted listing keeps its row, its likes and its matches. The app hides it
-- from Discover and My Listings, while conversations about it keep working.
-- ---------------------------------------------------------------------------

alter table public.listings
  add column if not exists "deletedAt" bigint;

create index if not exists listings_deleted_idx
  on public.listings ("deletedAt");

-- Readable by any signed-in account except rows deleted by another owner.
-- The owner still sees their own deleted row so an accidental delete can be
-- inspected; the client filters it out of every deck.
drop policy if exists "listings_select_signed_in" on public.listings;
create policy "listings_select_signed_in" on public.listings
  for select to authenticated
  using (
    "deletedAt" is null
    or "ownerUid" = (select auth.uid())
  );

-- A listing that is gone must not collect new interest.
drop policy if exists "likes_insert_self_pending" on public.listing_likes;
create policy "likes_insert_self_pending" on public.listing_likes
  for insert to authenticated
  with check (
    public.is_verified()
    and "requesterUid" = (select auth.uid())
    and "status" = 'pending'
    and exists (
      select 1
      from public.listings l
      where l."id" = "listingId"
        and l."deletedAt" is null
        and l."ownerUid" <> (select auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- Realtime repair
--
-- 0003 added these tables to the publication, but a partially applied project
-- silently keeps returning only the first snapshot. Re-asserting replica
-- identity and publication membership makes cross-account updates arrive
-- without reopening the screen.
-- ---------------------------------------------------------------------------

alter table public.listings      replica identity full;
alter table public.listing_likes replica identity full;
alter table public.matches       replica identity full;
alter table public.messages      replica identity full;

do $$
declare
  target text;
begin
  foreach target in array array['listings', 'listing_likes', 'matches', 'messages']
  loop
    begin
      execute format(
        'alter publication supabase_realtime add table public.%I',
        target
      );
    exception
      when duplicate_object then null;
      when undefined_object then null;
    end;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Message inserts update the match summary in the same transaction
--
-- The Dart client no longer writes messagesCount/lastMessage itself. A
-- proposal message also moves the match to "proposed" in the same statement,
-- so a slow or failed second request can no longer leave the two sides out of
-- sync.
-- ---------------------------------------------------------------------------

create or replace function public.apply_message_to_match()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.matches m
  set "messagesCount" = m."messagesCount" + 1,
      "lastMessage" = new."text",
      "viewingStatus" = case
        when new."type" = 'viewingProposal' then 'proposed'
        else m."viewingStatus"
      end,
      "viewingDate" = case
        when new."type" = 'viewingProposal' then new."viewingDate"
        else m."viewingDate"
      end,
      "updatedAt" = (extract(epoch from clock_timestamp()) * 1000)::bigint
  where m."id" = new."matchId";

  if not found then
    raise exception 'Match % does not exist', new."matchId"
      using errcode = 'foreign_key_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists messages_apply_to_match on public.messages;
create trigger messages_apply_to_match
  after insert on public.messages
  for each row execute function public.apply_message_to_match();

-- ---------------------------------------------------------------------------
-- Proposal responses update the match in the same transaction
-- ---------------------------------------------------------------------------

create or replace function public.apply_proposal_response()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."type" = 'viewingProposal'
     and new."proposalStatus" is distinct from old."proposalStatus" then
    update public.matches m
    set "viewingStatus" = case new."proposalStatus"
          when 'accepted' then 'confirmed'
          when 'declined' then 'declined'
          else 'proposed'
        end,
        "viewingDate" = coalesce(new."viewingDate", m."viewingDate"),
        "updatedAt" = (extract(epoch from clock_timestamp()) * 1000)::bigint
    where m."id" = new."matchId";
  end if;

  return new;
end;
$$;

drop trigger if exists messages_apply_proposal_response on public.messages;
create trigger messages_apply_proposal_response
  after update of "proposalStatus" on public.messages
  for each row execute function public.apply_proposal_response();

-- ---------------------------------------------------------------------------
-- Recipient-only proposal responses
--
-- RLS cannot express "not the sender" reliably for a partial UPDATE without
-- also exposing a direct write path. This function is the single supported
-- way to accept or decline: it checks the caller, the proposal state and the
-- match state, then updates the message. The trigger above moves the match.
-- ---------------------------------------------------------------------------

create or replace function public.respond_to_viewing_proposal(
  p_match_id text,
  p_message_id text,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match public.matches%rowtype;
  v_sender uuid;
  v_type text;
  v_current text;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  if p_status is null or p_status not in ('accepted', 'declined') then
    raise exception 'A proposal can only be accepted or declined'
      using errcode = '22023';
  end if;

  select *
    into v_match
  from public.matches m
  where m."id" = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if not ((select auth.uid()) = any (v_match."participantUids")) then
    raise exception 'Only match participants can respond'
      using errcode = '42501';
  end if;

  if v_match."status" <> 'active' then
    raise exception 'This conversation is closed' using errcode = 'P0001';
  end if;

  select msg."senderUid", msg."type", msg."proposalStatus"
    into v_sender, v_type, v_current
  from public.messages msg
  where msg."id" = p_message_id
    and msg."matchId" = p_match_id;

  if not found then
    raise exception 'Proposal not found' using errcode = 'P0002';
  end if;

  if v_type <> 'viewingProposal' then
    raise exception 'That message is not a viewing proposal'
      using errcode = 'P0001';
  end if;

  if v_sender = (select auth.uid()) then
    raise exception 'You cannot respond to your own proposal'
      using errcode = '42501';
  end if;

  if v_current <> 'pending' then
    raise exception 'This proposal was already answered'
      using errcode = 'P0001';
  end if;

  update public.messages msg
  set "proposalStatus" = p_status
  where msg."id" = p_message_id
    and msg."matchId" = p_match_id;
end;
$$;

revoke all on function public.respond_to_viewing_proposal(text, text, text)
  from public;
grant execute on function public.respond_to_viewing_proposal(text, text, text)
  to authenticated;

-- Direct message updates remain possible for the legacy two-write fallback,
-- but only the recipient of a still-pending proposal may use them. Text,
-- sender and timing are protected by messages_freeze_identity from 0002.
drop policy if exists "messages_update_participant" on public.messages;
create policy "messages_update_participant" on public.messages
  for update to authenticated
  using (
    "type" = 'viewingProposal'
    and "proposalStatus" = 'pending'
    and "senderUid" <> (select auth.uid())
    and exists (
      select 1
      from public.matches m
      where m."id" = "matchId"
        and (select auth.uid()) = any (m."participantUids")
        and m."status" = 'active'
    )
  )
  with check (
    "type" = 'viewingProposal'
    and "proposalStatus" in ('accepted', 'declined')
    and "senderUid" <> (select auth.uid())
    and exists (
      select 1
      from public.matches m
      where m."id" = "matchId"
        and (select auth.uid()) = any (m."participantUids")
        and m."status" = 'active'
    )
  );

-- ---------------------------------------------------------------------------
-- Message writes require an active match
-- ---------------------------------------------------------------------------

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
        and m."status" = 'active'
    )
  );

-- ---------------------------------------------------------------------------
-- Atomic interest approval
--
-- Creates the deterministic match and closes the like in one transaction. The
-- caller must be the listing owner, the listing must still exist, and the
-- requester must have a real pending/approved like.
-- ---------------------------------------------------------------------------

create or replace function public.approve_interest(
  p_listing_id text,
  p_requester_uid uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_listing public.listings%rowtype;
  v_now bigint;
  v_match_id text;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  select *
    into v_listing
  from public.listings l
  where l."id" = p_listing_id
    and l."deletedAt" is null;

  if not found then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;

  if v_listing."ownerUid" <> (select auth.uid()) then
    raise exception 'Only the listing owner can approve interest'
      using errcode = '42501';
  end if;

  if p_requester_uid = (select auth.uid()) then
    raise exception 'You cannot approve your own interest'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.listing_likes ll
    where ll."listingId" = p_listing_id
      and ll."requesterUid" = p_requester_uid
  ) then
    raise exception 'No interest request found' using errcode = 'P0002';
  end if;

  v_now := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_match_id := p_listing_id || '_' || p_requester_uid::text;

  insert into public.matches (
    "id",
    "listingId",
    "listingTitle",
    "ownerUid",
    "requesterUid",
    "participantUids",
    "status",
    "matchedAt",
    "expiresAt",
    "messagesCount",
    "lastMessage",
    "viewingStatus",
    "viewingDate",
    "updatedAt"
  ) values (
    v_match_id,
    p_listing_id,
    v_listing."title",
    v_listing."ownerUid",
    p_requester_uid,
    array[v_listing."ownerUid", p_requester_uid],
    'active',
    v_now,
    v_now + (24 * 60 * 60 * 1000),
    0,
    '',
    'none',
    null,
    v_now
  )
  on conflict ("id") do nothing;

  update public.listing_likes ll
  set "status" = 'approved',
      "approvedAt" = v_now
  where ll."listingId" = p_listing_id
    and ll."requesterUid" = p_requester_uid;
end;
$$;

revoke all on function public.approve_interest(text, uuid) from public;
grant execute on function public.approve_interest(text, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Repair summaries left behind by the old two-write client
-- ---------------------------------------------------------------------------

update public.matches m
set "messagesCount" = stats.message_count,
    "lastMessage" = coalesce(stats.last_text, ''),
    "updatedAt" = (extract(epoch from clock_timestamp()) * 1000)::bigint
from (
  select
    msg."matchId" as match_id,
    count(*)::int as message_count,
    (array_agg(msg."text" order by msg."sentAt" desc, msg."id" desc))[1]
      as last_text
  from public.messages msg
  group by msg."matchId"
) stats
where stats.match_id = m."id"
  and (
    m."messagesCount" <> stats.message_count
    or m."lastMessage" <> coalesce(stats.last_text, '')
  );

commit;
