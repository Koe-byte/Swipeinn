# Swipeinn

**Swipe. Match. Move in.**

Swipeinn is a bilateral rental discovery app. Owners list places, renters swipe through them, and a conversation opens only when both sides express interest. Chat and viewing proposals happen inside the match.

## Current status

Phase 0: Swipeinn rebrand and Firebase/Android setup.

The app is being migrated from the original student-only Rently demo. Demo authentication, seeded listings, sample likes/matches, and simulated chat replies are removed in Phase 1, followed by the real Firestore data model and rules in Phase 2.

## Stack

- Flutter 3.47 / Dart 3.13
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
