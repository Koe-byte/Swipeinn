# Swipeinn

**Swipe. Match. Move in.**

Swipeinn is a bilateral rental discovery app. Owners list places, renters swipe through them, and a conversation opens only when both sides express interest. Chat and viewing proposals happen inside the match.

## Current status

Phase 4: Supabase backend.

- The app now runs on **Supabase** for everything: Auth, Postgres (with
  Realtime), and Storage. Firebase is gone — dependencies, config files, Gradle
  plugins and hosting. See [`docs/adr/0007-supabase-backend.md`](docs/adr/0007-supabase-backend.md).
- Listings, likes, matches and messages live in five Postgres tables behind Row
  Level Security. `DatabaseService` keeps its offline mirror and now queues
  failed writes for replay instead of relying on Firestore's built-in queue.
- **Photo upload works.** Owners pick up to five images in the publish/edit form;
  they upload to the `listing-photos` bucket on save and render everywhere a
  listing appears.
- Subcollections became flat tables: `listing_likes` and `messages` carry a
  foreign key instead of a parent path.

Phase 3: app structure.

- Every listing opens a full detail screen with photos, description, amenities,
  location, and status.
- Owners get **Review Queue**, **Edit listing**, and **Delete listing** on their
  own listings. Deleting asks for confirmation and only the owner can do it.
- Publishing and editing share one form. Its save button is pinned to the bottom
  so a long form never hides the action.
- **Profile** is its own feature now: rename the account inline, review search
  preferences, and edit them with the same two-step form used at onboarding.
- Tabs keep their state (`IndexedStack`), and open screens are named routes built
  by `AppRouter`, so detail/editor/review/preferences all share one route table.

Phase 2: real persistence.

- Listings, likes, matches, and messages survive reloads and devices. Both sides
  of a match see it live.
- Listings use one `PropertyType` enum shared with onboarding, and owner /
  requester fields instead of the old landlord / student names.
- Matches are keyed by `participantUids`, so one indexed array lookup returns the
  conversations for whichever side of the match is signed in.
- RLS requires a confirmed email for writes, lets only the listing owner read the
  likes queue, and only the owner can open a match from an existing like.
- No demo accounts, demo buttons, local-auth fallback, seeded data, or simulated
  replies.

## Demo script

Use two browsers or one normal + one incognito window. Each needs its own
account.

1. `flutter run -d chrome --dart-define-from-file=supabase.env.json`.
2. Create account **A**, then finish the two onboarding steps. Email confirmation
   is disabled on this project, so sign-up lands straight in onboarding.
3. Repeat for account **B** in the other window.
4. As **A**, publish a place from **My Listings**, adding at least one photo.
   Tapping the card opens the detail screen, where **Edit listing** and
   **Delete listing** live.
5. As **B**, open **Discover**, tap a card to read the full listing, or tap the
   heart to express interest.
6. As **A**, open **My Listings → Review Queue** and tap **Approve**.
7. Both accounts now see the match under **Matches**. B sends the first
   message; A can read it and reply. A viewing proposal can be scheduled and
   accepted inside the chat.

## Stack

- Flutter 3.47.9 (pinned) / Dart 3.13.7 — see [`docs/TOOLCHAIN.md`](docs/TOOLCHAIN.md)
- Supabase Auth, Postgres + Realtime, Supabase Storage
- Riverpod

## Supabase

- Project ref: `bjvsuzpqnzpdacxreqrl`
- API URL: `https://bjvsuzpqnzpdacxreqrl.supabase.co`
- Android package: `com.swipeinn.app`
- Hosted web app: Cloudflare Workers static assets (`build/web`, `wrangler.jsonc`)

See [`docs/SUPABASE_SETUP.md`](docs/SUPABASE_SETUP.md) for setup details.

## Project structure

```
lib/
  core/        navigation (AppRouter, AppRoutes), services, theme, shared widgets
  features/
    auth/      sign-in, verification, onboarding + preferences editor
    listings/  models, repository, Discover, My Listings, detail, editor, queue
    matches/   match list and chat
    profile/   account hub (rename, preferences, sign out)
    navigation/main shell: auth gate + four preserved tabs
```

## Development

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --dart-define-from-file=supabase.env.json
flutter run -d emulator-5554 --dart-define-from-file=supabase.env.json
```

Create `supabase.env.json` from `supabase.env.example.json` first; it is
gitignored. Android builds no longer need `google-services.json` or a FlutterFire
Gradle plugin.

## Product direction

Swipeinn is a general rental marketplace, not a student-only app. One account
can both browse listings and list a place. Student-only concepts such as campus
verification and dorm demographics are being replaced with general search
preferences and an admin-reviewed owner badge.
