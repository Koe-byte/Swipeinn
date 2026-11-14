# Swipeinn

**Swipe. Match. Move in.**

Swipeinn is a bilateral rental discovery app. Owners list places, renters swipe through them, and a conversation opens only when both sides express interest. Chat and viewing proposals happen inside the match.

## Current status

Phase 3: app structure.

- Every listing opens a full detail screen with photos (placeholder until upload
  lands), description, amenities, location, and status.
- Owners get **Review Queue**, **Edit listing**, and **Delete listing** on their
  own listings. Deleting asks for confirmation and only the owner can do it.
- Publishing and editing share one form. Its save button is pinned to the bottom
  so a long form never hides the action.
- **Profile** is its own feature now: rename the account inline, review search
  preferences, and edit them with the same two-step form used at onboarding.
- Tabs keep their state (`IndexedStack`), and open screens are named routes built
  by `AppRouter`, so detail/editor/review/preferences all share one route table.

Phase 2: real Firestore persistence.

- Listings, likes, matches, and messages are stored in Cloud Firestore and
  survive reloads and devices. Both sides of a match see it live.
- Listings use one `PropertyType` enum shared with onboarding, and owner /
  requester fields instead of the old landlord / student names.
- Matches are keyed by `participantUids`, so one `array-contains` query returns
  the conversations for whichever side of the match is signed in.
- `firestore.rules` requires a verified email for writes, lets only the listing
  owner read the likes queue, and only the owner can open a match from an
  existing like. The rules suite passes 27 emulator checks.
- The full publish → like → approve → chat loop needs two accounts. One account
  can still publish and preview its own card; liking your own place is blocked
  both in the UI and by the rules.
- No demo accounts, demo buttons, local-auth fallback, seeded data, or simulated
  replies. Photo upload is still blocked until Firebase Storage is enabled.

## Demo script

Use two browsers or one normal + one incognito window. Each needs its own
verified account.

1. `flutter run -d chrome` (or open the hosted build).
2. Create account **A** with an address you can open, click the verification
   link, then "I've verified my email", and finish the two onboarding steps.
3. Repeat for account **B** in the other window.
4. As **A**, publish a place from **My Listings**. Tapping it opens the detail
   screen, where **Edit listing** and **Delete listing** live.
5. As **B**, open **Discover**, tap a card to read the full listing, or tap the
   heart to express interest.
6. As **A**, open **My Listings → Review Queue** and tap **Approve**.
7. Both accounts now see the match under **Matches**. B sends the first
   message; A can read it and reply. A viewing proposal can be scheduled and
   accepted inside the chat.

## Stack

- Flutter 3.47.9 (pinned) / Dart 3.13.7 — see [`docs/TOOLCHAIN.md`](docs/TOOLCHAIN.md)
- Firebase Auth, Cloud Firestore, Firebase Storage
- Riverpod

## Firebase

- Firebase project ID: `rently-ph` (kept for continuity)
- Android package: `com.swipeinn.app`
- Hosted web app: `https://swipeinn.web.app`

See [`docs/FIREBASE_SETUP.md`](docs/FIREBASE_SETUP.md) for setup details.

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
flutter run -d chrome
flutter run -d emulator-5554
```

Android builds require the Firebase Android app registration and
`android/app/google-services.json`.

## Product direction

Swipeinn is a general rental marketplace, not a student-only app. One account
can both browse listings and list a place. Student-only concepts such as campus
verification and dorm demographics are being replaced with general search
preferences and an admin-reviewed owner badge.
