# Supabase as the single Backend

Swipeinn moved off Firebase entirely: Supabase Auth replaces Firebase Auth,
Postgres + Realtime replace Cloud Firestore, and Supabase Storage replaces
Firebase Storage. The trigger was practical — Firebase Storage was never
provisioned on the `rently-ph` project because Cloud Billing was disabled, which
left photo upload blocked behind a billing plan the project did not want.

The migration is deliberately shallow. Three files ever imported Firebase:
`main.dart`, `auth_repository.dart`, and `core/services/database_service.dart`.
Every repository and screen already went through those, so the swap happens
inside one service plus one repository rather than across the app.

## Collection shape

Firestore's nested collections became flat tables:

| Before | After |
| --- | --- |
| `users/{uid}` | `public.users` (`uid` primary key) |
| `listings/{listingId}` | `public.listings` (`id` text primary key) |
| `listings/{listingId}/likes/{uid}` | `public.listing_likes` (`listingId`, `requesterUid`) |
| `matches/{matchId}` | `public.matches` (`id` text primary key) |
| `matches/{matchId}/messages/{id}` | `public.messages` (`matchId` foreign key) |

`DatabaseService` keeps its collection/document vocabulary and holds the only
two mappings that know about the new shape: a table/primary-key registry and a
subcollection registry. Nothing above it changed.

Column names stay camelCase and are quoted, because the models already emit
camelCase maps. A snake_case schema would have required a translation layer in
the hot data path for no benefit to any caller.

## Security

`firestore.rules` and `storage.rules` became RLS policies in
`supabase/migrations/0002_security.sql` and `0003_storage_realtime.sql`. Two
translations were not mechanical:

- Firestore read `email_verified` from the ID token. The Supabase JWT has no such
  claim, so `public.is_verified()` is a `security definer` function reading
  `auth.users.email_confirmed_at`.
- Firestore expressed "only these columns may change" with
  `affectedKeys().hasOnly([...])`. Postgres can express that with column-level
  `GRANT UPDATE`, but the client writes rows through a merge (UPDATE, then
  INSERT when absent), and Postgres checks column privileges before it knows
  whether any row matched — so a partial grant rejects even the first insert.
  The equivalent is a `before update` trigger per table: one freezes a like's
  requester fields, one freezes match participants, one freezes message content.
  The approval fields and the viewing-proposal fields remain writable.

Writes are default-deny: RLS is on for every table, and `anon` holds no grants.
The client ships a publishable key, which is fine — RLS is the boundary.

## Consequences

- **Email confirmation is off.** With confirmation enabled, Supabase refuses to
  create a session until the address is confirmed, so the app's existing
  "signed in but unverified" gate would be unreachable. Autoconfirm keeps
  `AuthIdentity.isEmailVerified` true from the first sign-up, which means the
  verification screen stays in the codebase but is no longer part of the demo
  path. Turning confirmation on later requires reworking that gate, not a policy
  change.
- **Offline writes are queued by the app, not the backend.** Firestore's SDK
  queued writes itself; PostgREST does not. `DatabaseService` now persists failed
  writes and replays them on the next launch or successful write, so an edit made
  offline is delayed rather than lost.
- **Streams subscribe per table, then filter in Dart.** RLS already scopes rows
  to the account, and repositories already sorted client-side to avoid composite
  indexes. At marketplace scale this is one subscription per screen, matching the
  previous listener count.
- **Photo storage is public-read, write-own-folder.** The bucket holds no
  private data — listing photos are shown to every signed-in account anyway.
  Uploads are still restricted to `users/{uid}/listings/{listingId}/...`, images
  only, 5 MB.
- **Web hosting left Firebase too.** `firebase.json`, `.firebaserc` and the
  FlutterFire Gradle plugins are gone; the web build is served from Cloudflare
  Pages with a SPA fallback in `web/_redirects`.
- **The free tier pauses idle projects.** A Supabase free project is paused after
  about a week of inactivity, which is acceptable for a demo and not acceptable
  for a live marketplace.
