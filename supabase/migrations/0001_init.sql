-- Swipeinn schema.
--
-- The previous backend stored five Firestore collections, two of which were
-- subcollections. They become flat Postgres tables here:
--
--   users                              -> public.users
--   listings                           -> public.listings
--   listings/{listingId}/likes         -> public.listing_likes
--   matches                            -> public.matches
--   matches/{matchId}/messages         -> public.messages
--
-- Column names stay camelCase on purpose. The Dart models already produce and
-- consume camelCase maps (ListingModel.toMap/fromMap and friends), so keeping
-- the names identical lets DatabaseService stay a generic table gateway with no
-- key translation layer. Every identifier that needs it is quoted.
--
-- Timestamps are bigint epoch milliseconds because that is what the models
-- already read and write; mixing in timestamptz would force a conversion at
-- every boundary for no benefit.

begin;

-- One row per account. The primary key is the Supabase auth user id.
create table if not exists public.users (
  "uid"                   uuid primary key references auth.users (id) on delete cascade,
  "email"                 text        not null default '',
  "displayName"           text        not null default '',
  "photoUrl"              text        not null default '',
  "authProvider"          text        not null default 'password',
  "isOwnerVerified"       boolean     not null default false,
  "hasCompletedOnboarding" boolean    not null default false,
  "preferences"           jsonb,
  "createdAt"             bigint      not null default 0,
  "updatedAt"             bigint
);

-- Places published by any account.
create table if not exists public.listings (
  "id"            text primary key,
  "ownerUid"      uuid        not null references auth.users (id) on delete cascade,
  "title"         text        not null default '',
  "description"   text        not null default '',
  "monthlyRent"   double precision not null default 0,
  "propertyType"  text        not null default 'room',
  "photos"        text[]      not null default '{}',
  "amenities"     text[]      not null default '{}',
  "latitude"      double precision not null default 0,
  "longitude"     double precision not null default 0,
  "status"        text        not null default 'available',
  "createdAt"     bigint      not null default 0,
  "updatedAt"     bigint
);

create index if not exists listings_owner_idx on public.listings ("ownerUid");
create index if not exists listings_created_idx on public.listings ("createdAt" desc);

-- One interest request per requester, per listing. The composite primary key is
-- the same rule the Firestore document id enforced: you cannot like a place
-- twice. Rows are never deleted on approval; history is kept.
create table if not exists public.listing_likes (
  "listingId"      text not null references public.listings ("id") on delete cascade,
  "requesterUid"   uuid not null references auth.users (id) on delete cascade,
  "requesterName"  text not null default '',
  "likedAt"        bigint not null default 0,
  "status"         text not null default 'pending',
  "approvedAt"     bigint,
  primary key ("listingId", "requesterUid")
);

create index if not exists listing_likes_listing_idx on public.listing_likes ("listingId");

-- A conversation opened when an owner approves a like. The id is deterministic:
-- "${listingId}_${requesterUid}".
create table if not exists public.matches (
  "id"               text primary key,
  "listingId"        text not null references public.listings ("id") on delete cascade,
  "listingTitle"     text not null default '',
  "ownerUid"         uuid not null references auth.users (id) on delete cascade,
  "requesterUid"     uuid not null references auth.users (id) on delete cascade,
  "participantUids"  uuid[] not null default '{}',
  "status"           text not null default 'active',
  "matchedAt"        bigint not null default 0,
  "expiresAt"        bigint not null default 0,
  "messagesCount"    integer not null default 0,
  "lastMessage"      text not null default '',
  "viewingStatus"    text not null default 'none',
  "viewingDate"      bigint,
  "updatedAt"        bigint
);

-- "Matches for me" is one indexed array lookup instead of two OR queries.
create index if not exists matches_participants_idx
  on public.matches using gin ("participantUids");
create index if not exists matches_listing_idx on public.matches ("listingId");

create table if not exists public.messages (
  "id"              text primary key,
  "matchId"         text not null references public.matches ("id") on delete cascade,
  "senderUid"       uuid not null references auth.users (id) on delete cascade,
  "text"            text not null default '',
  "type"            text not null default 'text',
  "viewingDate"     bigint,
  "proposalStatus"  text not null default 'pending',
  "sentAt"          bigint not null default 0
);

create index if not exists messages_match_idx on public.messages ("matchId", "sentAt");

commit;
