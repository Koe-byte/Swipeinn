# Firebase setup for Rently

Project: `rently-ph` (see `.firebaserc` and `lib/firebase_options.dart`).

## 1. Enable Authentication providers

In the [Firebase Console](https://console.firebase.google.com/project/rently-ph/authentication/providers):

1. **Email/Password** — enable it. This is required for:
   - normal email/password sign-up and sign-in
   - the fixed demo accounts below
2. **Google** — enable it for Google sign-in.
3. **Facebook** — enable it for Facebook sign-in (only `public_profile` is requested).

Under **Authentication → Settings → Authorized domains**, add every domain used
for local/staging web builds (for example `localhost`, your LAN IP, and the
production host).

## 2. Deploy Firestore rules

The rules in `firestore.rules` make `users/{auth.uid}` the source of truth and
scope matches/messages to their participants.

```powershell
npm install -g firebase-tools
firebase login
firebase use rently-ph
firebase deploy --only firestore:rules
```

Or without a global install:

```powershell
npx firebase-tools login
npx firebase-tools use rently-ph
npx firebase-tools deploy --only firestore:rules
```

Indexes are not required for the current queries, but the config is included:

```powershell
firebase deploy --only firestore:indexes
```

## 3. Demo accounts

The debug demo buttons use these fixed accounts:

| Role   | Email                  | Password        |
| ------ | ---------------------- | --------------- |
| Student | `student.demo@rently.ph` | `RentlyDemo123!` |
| Host    | `host.demo@rently.ph`    | `RentlyDemo123!` |

Once Email/Password is enabled, tap **Student demo** / **Host demo** on the
signed-out landing screen (debug builds only). On first use the app creates the
Firebase Auth account and its `users/{uid}` profile automatically. Subsequent
sign-ins reuse the same uid and profile.

To create them manually instead, use **Authentication → Users → Add user** with
the same email/password, then sign in through the demo button once so the app
writes the profile document.

### Demo account troubleshooting

The app never substitutes a local identity when Firebase Auth is configured.
If a demo button shows:

> The demo account `host.demo@rently.ph` exists with a different password.
> Reset it to `RentlyDemo123!` in Firebase Console > Authentication > Users,
> or delete the account and try again.

then the Auth user exists with a different password or provider. Open
[Authentication → Users](https://console.firebase.google.com/project/rently-ph/authentication/users),
delete `host.demo@rently.ph`, and tap **Host demo** again. Deleting is safer
than guessing the old password.

If Email/Password is disabled, the demo buttons surface an
`operation-not-allowed` error instead of silently falling back to a mock
identity. Enable the provider first.

## 4. What the app writes

- `users/{auth.uid}` — profile, role, onboarding state (owner-only)
- `matches/{matchId}` — bilateral match (participants only)
- `matches/{matchId}/messages/{messageId}` — chat (participants only; message
  text and sender are immutable after creation)
- `settings/{auth.uid}` — per-user preferences (owner-only)

Synthetic IDs such as `student_sample_1` are only used by the local/debug
fallback. Real accounts always use the Firebase Auth uid. The app also repairs
a missing `users/{uid}` document automatically: if the profile is still in the
durable local cache, the next sign-in re-uploads it to Firestore.
