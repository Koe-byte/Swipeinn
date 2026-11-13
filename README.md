# Swipeinn

**Swipe. Match. Move in.**

Swipeinn is a bilateral rental discovery app. Owners list places, renters swipe through them, and a conversation opens only when both sides express interest. Chat and viewing proposals happen inside the match.

## Current status

Phase 1: real email/password authentication.

- Sign-up creates a Firebase Auth account and sends a verification email. The
  app stays at the verification gate until the address is confirmed.
- A required two-step preferences flow (property type + budget, then areas +
  move-in window) runs once per account and is stored in `users/{uid}`.
- One account can browse and publish; the only badge is the admin-granted
  "Verified owner" flag.
- Demo accounts, demo buttons, the local-auth fallback, seeded listings, sample
  likes/matches, and simulated chat replies are gone.
- Listings and matches still live in memory for v1; Firestore persistence and
  rules are Phase 2. A match created in a session is available until the app
  restarts.

## Demo script

1. `flutter run -d chrome` (or open the hosted build).
2. Create an account with an address you can open.
3. Click the verification link, then "I've verified my email".
4. Complete the two onboarding steps.
5. Publish a place from **My Listings**, like it from **Discover**, approve the
   interest from that listing's **Review Queue**, and open **Matches** to chat.

## Stack

- Flutter 3.47.9 (pinned) / Dart 3.13.7 — see [`docs/TOOLCHAIN.md`](docs/TOOLCHAIN.md)
- Firebase Auth, Cloud Firestore, Firebase Storage
- Riverpod

## Firebase

- Firebase project ID: `rently-ph` (kept for continuity)
- Android package: `com.swipeinn.app`
- Hosted web app: `https://swipeinn.web.app` (deployed in Phase 5)

See [`docs/FIREBASE_SETUP.md`](docs/FIREBASE_SETUP.md) for setup details.

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
