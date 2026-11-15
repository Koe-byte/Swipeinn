# Supabase setup for Swipeinn

Everything the app needs lives in one Supabase project. There is no second
database, no server, and no build-time secret.

## 1. Project resources

| Item | Value |
| --- | --- |
| Project ref | `bjvsuzpqnzpdacxreqrl` |
| API URL | `https://bjvsuzpqnzpdacxreqrl.supabase.co` |
| Dashboard | <https://supabase.com/dashboard/project/bjvsuzpqnzpdacxreqrl> |
| Region | matches the project's creation settings |
| Storage bucket | `listing-photos` (public read) |

The **publishable key** (`sb_publishable_...`) goes in `supabase.env.json`. It is
safe to ship inside the client: it identifies the app, not the user, and Row
Level Security decides what the user may touch. The **secret key**
(`sb_secret_...`, formerly `service_role`) bypasses RLS and must never appear in
the app, in git, or in a browser.

There is no Postgres connection string in this project on purpose. The Flutter
client talks to the Data API over HTTPS; a `postgresql://` URI is only for
running migrations or `pg_dump` from a laptop, and on the free plan the direct
connection is IPv6-only, so use the **session pooler** string from **Connect** if
you ever need one.

## 2. Run the migrations

In order, in the SQL editor (<https://supabase.com/dashboard/project/bjvsuzpqnzpdacxreqrl/sql/new>):

1. `supabase/migrations/0001_init.sql` — tables, indexes, foreign keys.
2. `supabase/migrations/0002_security.sql` — RLS policies, grants, helper
   function, immutability trigger.
3. `supabase/migrations/0003_storage_realtime.sql` — bucket, storage policies,
   realtime publication.

Each file is idempotent enough to re-run: tables use `if not exists`, policies are
dropped before creation, and the publication loop ignores duplicates.

With the CLI instead of the dashboard:

```powershell
npx supabase login
npx supabase link --project-ref bjvsuzpqnzpdacxreqrl
npx supabase db push
```

## 3. Dashboard settings that the migrations cannot set

**Authentication → Sign In / Providers → Email**

- Leave Email enabled.
- Turn **Confirm email** off. This is what keeps the current sign-up flow: the
  session exists immediately and `emailVerified` is true from the start. See
  `docs/adr/0007-supabase-backend.md` for why the verification gate is now
  dormant rather than removed.

**Authentication → URL Configuration**

- Site URL: `http://localhost:8080`
- Redirect URLs: add `https://<your-app>.pages.dev` (password-reset links land
  here).

## 4. Point the app at the project

```powershell
Copy-Item supabase.env.example.json supabase.env.json
```

Fill in the two values, then always run with the define file:

```powershell
flutter run -d chrome --dart-define-from-file=supabase.env.json
flutter run -d emulator-5554 --dart-define-from-file=supabase.env.json
flutter build web --release --dart-define-from-file=supabase.env.json
```

`supabase.env.json` is gitignored. Building without it shows the
"could not connect" screen instead of failing silently, because
`SupabaseConfig.assertConfigured()` runs before `Supabase.initialize`.

## 5. Web hosting (Cloudflare Pages)

| Setting | Value |
| --- | --- |
| Build command | `flutter build web --release --dart-define-from-file=supabase.env.json` |
| Output directory | `build/web` |
| Env vars | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` |

Cloudflare needs the two values as build environment variables so the build
command can be shortened to `flutter build web --release` with
`--dart-define=SUPABASE_URL=$SUPABASE_URL` style flags, or the env file can be
written during the build. `web/_redirects` already contains the SPA fallback.

## 6. Photo uploads

- Bucket `listing-photos`, public read, 5 MB per object, `image/*` only.
- Object path: `users/{uid}/listings/{listingId}/{fileName}`.
- Storage RLS reads the uploader from **folder element 2** of the path, not
  element 1. Path element 1 is the literal `users` segment.
- The editor uploads only on save, so cancelling an edit stores nothing.
- Removing a photo deletes the object after the listing row is saved, and
  deleting a listing best-effort deletes all of its objects. A failed delete is
  ignored and leaves an orphan; it never fails the edit.

## 7. Security model

Full detail is in `supabase/migrations/0002_security.sql`. In short:

- `users` — owner-only read/write.
- `listings` — readable by any signed-in account, writable by the verified owner.
- `listing_likes` — the requester sees their own row, the listing owner sees the
  queue; only the owner may approve, and a trigger keeps the requester fields
  immutable.
- `matches` — participants only; creation requires an existing like on the
  owner's own listing; participant columns are frozen by a trigger.
- `messages` — participants only; the sender must be the writer; a trigger keeps
  message content immutable, so only `proposalStatus` and `viewingDate` move.

`is_verified()` reads `auth.users.email_confirmed_at` because the JWT carries no
`email_verified` claim. If every write suddenly returns permission-denied for a
correctly signed-in user, check that function before the policies.

## 8. Verification checklist

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --dart-define-from-file=supabase.env.json
```

Then, with two verified accounts in two browsers:

1. Account A publishes a place **with at least one photo**; the photo appears in
   My Listings, Discover and the detail screen.
2. Account B likes it, A approves from the Review Queue, both see the match.
3. A and B exchange messages; a viewing proposal can be accepted in chat.
4. A edits the listing, removes a photo, and saves; the object disappears from
   the bucket.
5. A deletes the listing; the row is gone from Discover for B.

## 9. Common failures

| Symptom | Cause |
| --- | --- |
| "Supabase is not configured" startup screen | Missing `--dart-define-from-file`. |
| Sign-up succeeds but nothing is stored | Migrations not applied, or RLS enabled without the policies file. |
| Every write is permission-denied | `public.is_verified()` missing, or email not confirmed with Confirm email on. |
| Streams show initial rows then freeze | Table missing from the `supabase_realtime` publication. |
| Streams work but updates from the other browser never arrive | `replica identity full` not set on the table. |
| Upload rejected with 403 | Path is not `users/{uid}/...`, file is over 5 MB, or not an image. |
| Photo URL 400/404 | Bucket is not public, or the object was uploaded under a different uid. |
| Reset link goes to the wrong place | Redirect URL missing in Authentication → URL Configuration. |
