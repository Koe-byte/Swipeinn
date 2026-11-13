# Firebase setup for Swipeinn

Swipeinn is the app-facing brand. The Firebase project ID remains `rently-ph`
for continuity; see `.firebaserc` and `lib/firebase_options.dart`.

## Project resources

| Resource | Value |
| --- | --- |
| Firebase project | `rently-ph` |
| Project display name | `Swipeinn` |
| Firestore database | `(default)`, `asia-southeast1` |
| Web app ID | `1:58561207998:web:524440ca2bea980e8388ef` |
| Android app ID | `1:58561207998:android:fa4e975bd1433c0a8388ef` |
| Android package | `com.swipeinn.app` |
| Hosting site | `swipeinn` → `https://swipeinn.web.app` |

## 1. Authentication

In the [Firebase Console](https://console.firebase.google.com/project/rently-ph/authentication/providers):

1. Enable **Email/Password**. This is the only sign-in method Swipeinn supports.
2. Disable Google, Facebook, phone, and anonymous sign-in. The Google/Facebook
   buttons and their code were removed in Phase 1.

Verified on 2026-11-13: a sign-in probe with a nonexistent account returns
`INVALID_LOGIN_CREDENTIALS`, which means Email/Password is enabled (a disabled
provider returns `OPERATION_NOT_ALLOWED`).

Under **Authentication → Settings → Authorized domains**, keep:

- `localhost`
- `rently-ph.firebaseapp.com`
- `rently-ph.web.app`
- `swipeinn.web.app`

The custom hosting site `swipeinn.web.app` was added through the Identity
Toolkit Admin API on 2026-11-11. If a new hosting site is created later, add it
to this list or web sign-in will fail with `auth/unauthorized-domain`.

Email verification and password reset use Firebase's default email templates.
Customize the sender name and templates in the Console before launch.

## 2. Firestore

Deploy rules and indexes:

```powershell
firebase use rently-ph
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

The rules in `firestore.rules` are still the original demo-era rules. They are
replaced in Phase 2 with the real listings, likes, matches, and messages model.
Do not treat the current rules as production-ready.

## 3. Storage (photo uploads)

Listing photos are uploaded to:

```text
users/{uid}/listings/{listingId}/{fileName}
```

`storage.rules` limits writes to the uploader's own folder, images only, and
5 MB per file.

**Current blocker:** Firebase Storage is not initialized on `rently-ph`, and
Cloud Billing is disabled for the project (verified 2026-11-12). There are no
Storage buckets. `firebase deploy --only storage` fails with:

> Firebase Storage has not been set up on project 'rently-ph'.

To enable uploads:

1. Open [Firebase Console → Storage](https://console.firebase.google.com/project/rently-ph/storage).
2. Click **Get Started** and choose the same region as Firestore
   (`asia-southeast1`).
3. Confirm the billing plan requirements shown by the Console.
4. Run `firebase deploy --only storage`.

Until Storage is enabled, listing creation falls back to photo URLs. Do not
ship a photo-upload UI that silently fails; hide the upload control or label it
as unavailable while this blocker is open.

## 4. Hosting

The web build is served from the `swipeinn` hosting target:

```powershell
flutter build web --release
firebase deploy --only hosting:swipeinn
```

`https://swipeinn.web.app` serves the Phase 1 Flutter build: real email/password
auth, the verification gate, and the two-step preferences onboarding. Deploy
again after each phase that changes user-facing behavior.

The old `https://rently-ph.web.app` site remains available for a future redirect.

## 5. Android

The Android app is registered as **Swipeinn Android** with package
`com.swipeinn.app`. Its configuration is stored in
`android/app/google-services.json`, and the Google Services Gradle plugin is
already applied.

```powershell
flutter build apk --debug --target-platform android-x64   # emulator only
flutter build apk --release --target-platform android-arm64  # installable on a phone
```

The arm64 release APK is debug-signed until a release keystore is configured.

`android/gradle.properties` caps Gradle at a 1.5 GB heap and two workers
because the development machine has 6 GB RAM. Raise those limits only on a
machine with more memory. The x86_64 target matches the local emulator; use
the default multi-ABI build for a physical device or release APK.

Release signing is not configured yet. A signed APK is part of the delivery
milestone after Phase 5.

## 6. Demo data and accounts

There are no supported demo accounts. The fixed `student.demo@rently.ph` and
`host.demo@rently.ph` users, the `RentlyDemo123!` password, and the demo buttons
on the landing screen were removed in Phase 1. Create a real account through
the app.

Seeded Firestore listings, likes, matches, and messages must be deleted before
real use. Back up the data first, then clear the collections in the Console or
with the Firestore Admin API. The Firebase CLI can delete documents but cannot
delete Auth users; remove those in **Authentication → Users** or with the Admin
SDK.

### Verified owner badge

`users/{uid}.isOwnerVerified` is admin-granted only. Set it to `true` in the
Firestore Console for accounts that should carry the badge. The app never writes
this field, and the badge is a trust signal rather than a permission: any
account can publish listings without it.

## 7. Local verification

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
flutter run -d emulator-5554
```

If web sign-in fails immediately, check the browser console for
`auth/unauthorized-domain` and confirm the current host is listed in
**Authentication → Settings → Authorized domains**.
