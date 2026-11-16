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
| Storage buckets | `listing-photos` and `avatars` (public read) |

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
3. `supabase/migrations/0003_storage_realtime.sql` — buckets, storage policies,
   realtime publication.
4. `supabase/migrations/0004_storage_avatars.sql` — repairs the storage policies
   if 0003's bucket exists without them, and adds the `avatars` bucket.

Each file is idempotent enough to re-run: tables use `if not exists`, policies are
dropped before creation, and the publication loop ignores duplicates.

`0004` is the one to re-run when a photo upload fails with
`403 new row violates row-level security policy`: that is the signature of a
bucket that exists while its write policies do not.

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

With confirmation off, `email_confirmed_at` is stamped at creation, so the
profile shows the address as **Verified**. The "Verify" action on that row only
appears for a session Supabase reports as unconfirmed (for example after an
email change), and it resends the confirmation link.

**Authentication → URL Configuration**

- Site URL: `https://swipeinn.ibonnash.workers.dev`
- Redirect URLs: add `https://swipeinn.ibonnash.workers.dev` and
  `http://localhost:8080` for local web runs. Confirmation and password-reset
  links land on the Site URL, so a `localhost` Site URL is unreachable from a
  phone.

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

## 5. Web hosting (Cloudflare Workers)

The site is deployed as a Worker with static assets, driven by `wrangler.jsonc`
at the repo root:

| Setting | Value |
| --- | --- |
| Build command | `flutter build web --release --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY` |
| Deploy command | `npx wrangler deploy` |
| Assets directory | `./build/web` (from `wrangler.jsonc`) |
| Build env vars | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` |

Two details that are easy to get wrong:

- `SupabaseConfig` reads `String.fromEnvironment`, which only understands
  `--dart-define`. Setting the two environment variables in the Cloudflare
  dashboard is not enough on its own; the build command has to forward them as
  `--dart-define=...` as shown above (or write `supabase.env.json` during the
  build and use `--dart-define-from-file`).
- SPA routing comes from `"not_found_handling": "single-page-application"` in
  `wrangler.jsonc`. Do **not** add `/* /index.html 200` to a `_redirects` file:
  Workers rejects it as an infinite loop because it strips `.html` from the
  target and matches the rule again. That rule is only valid on Pages.

## 6. Photo uploads

- Buckets: `listing-photos` and `avatars`, both public read, 5 MB per object,
  image MIME types only.
- Listing path: `users/{uid}/listings/{listingId}/{fileName}`.
- Avatar path: `users/{uid}/avatar_{timestamp}.{ext}`. A new name on every
  upload avoids a stale CDN copy; the previous object is deleted once the new
  URL is saved on the profile.
- Storage RLS reads the uploader from **folder element 2** of the path, not
  element 1. Path element 1 is the literal `users` segment.
- Size and MIME limits live on the bucket, not in the policy, so a missing
  metadata key cannot reject a valid upload.
- The listing editor uploads only on save, so cancelling an edit stores nothing.
- Removing a photo deletes the object after the listing row is saved, and
  deleting a listing best-effort deletes all of its objects. A failed delete is
  ignored and leaves an orphan; it never fails the edit.
- The profile picture is picked with `image_picker`, compressed to 900 px /
  quality 80, uploaded to `avatars`, then written to `users.photoUrl`. Removing
  it clears the column first and deletes the object afterwards.
- Storage failures surface as a `PhotoUploadException` with a readable message
  instead of a raw `StorageException` dump.

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
6. A opens Profile, taps the camera badge, picks a picture, and the new avatar
   appears immediately and after a cold restart. Removing it restores the
   initial.
7. A's profile shows the email row as **Verified** (Confirm email off).

## 9. Common failures

| Symptom | Cause |
| --- | --- |
| "Supabase is not configured" startup screen | Missing `--dart-define-from-file`. |
| Sign-up succeeds but nothing is stored | Migrations not applied, or RLS enabled without the policies file. |
| Every write is permission-denied | `public.is_verified()` missing, or email not confirmed with Confirm email on. |
| Streams show initial rows then freeze | Table missing from the `supabase_realtime` publication. |
| Streams work but updates from the other browser never arrive | `replica identity full` not set on the table. |
| Upload rejected with 403 | Storage policies missing while the bucket exists — run `0004_storage_avatars.sql`. Also check the path is `users/{uid}/...` and the file is a supported image under 5 MB. |
| Avatar upload rejected | Same as above, plus the file must use a MIME type allowed on the `avatars` bucket. |
| Photo URL 400/404 | Bucket is not public, or the object was uploaded under a different uid. |
| Reset link goes to the wrong place | Redirect URL missing in Authentication → URL Configuration. |
