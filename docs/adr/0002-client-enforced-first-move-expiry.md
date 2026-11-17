# First-Move Expiry (Removed for the MVP)

The original plan copied Bumble's 24-hour rule: a match stored
`expiresAt = matchedAt + 24h`, the Flutter client evaluated expiry on read, and
Firestore rules blocked the first message after that window. That rule is
**not active** in the current MVP.

## Why it was removed

- A match already means mutual consent: the owner approved the requester's
  interest. Forcing one side to move first added a hidden failure mode without
  adding safety.
- The rule was only enforced in the chat UI. The owner's composer was disabled,
  but the Schedule Viewing button still worked, so an owner could send the first
  message as a proposal.
- `messagesCount` was a separate client write. If the message insert succeeded
  and the count update failed, the owner stayed locked out even though the
  renter had messaged.
- `MatchModel.isExpired` always returned `false`, so the documented 24-hour
  timeout never actually happened.

## Current behavior

- Either participant can send the first text message or propose a viewing.
- A match ends only when a participant explicitly unmatches it.
- `expiresAt` and `remainingTime` remain on `MatchModel` for a future renewal
  flow, but nothing enforces them.
- Message inserts require `matches.status = 'active'`; this is the only
  conversation-lock rule the database enforces.

If first-move expiry comes back, it needs to be enforced by the database (not
just the composer), and proposal messages must count as a first move.
