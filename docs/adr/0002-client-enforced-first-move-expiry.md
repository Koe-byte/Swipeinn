# Client-Enforced 24-Hour First Move Expiry

To replicate the Bumble paradigm without paying for or configuring background Cloud Functions / scheduled cron jobs on Firebase, matches store an `expiresAt` timestamp set to `matchedAt + 24 hours`. The Flutter client passively evaluates expiry on read (`DateTime.now() > expiresAt` with `messagesCount == 0`) and Firestore Security Rules disallow message insertion once `request.time > resource.data.expiresAt` if `messagesCount == 0`.
