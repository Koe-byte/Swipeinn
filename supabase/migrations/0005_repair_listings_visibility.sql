-- Repair Discover visibility for deployments that applied an earlier or
-- partial security migration.
--
-- Discover must show every available listing, not just the current account's.
-- This migration is safe to re-run and does not change the write policies:
--   1. recreates the signed-in read policy on public.listings
--   2. restores the table grants the client expects
--   3. makes sure Realtime can stream the whole table
--
-- Run after 0001_init.sql and 0002_security.sql.

begin;

alter table public.listings enable row level security;

drop policy if exists "listings_select_signed_in" on public.listings;
create policy "listings_select_signed_in" on public.listings
  for select to authenticated
  using (true);

revoke all on public.listings from anon;
grant select, insert, update, delete on public.listings to authenticated;

-- UPDATE/DELETE RLS checks need the full row, and a table outside the
-- publication returns only its first snapshot to the Dart client.
alter table public.listings replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.listings;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end;
$$;

commit;
