# Structured Viewing Proposals Inside Real-Time Chat

Rather than relying entirely on free-form text where dates and inspection times
get lost, Rently renders an interactive **Viewing Proposal** message inside the
1-on-1 chat. Either participant can propose an in-person inspection by picking a
date. The message has `pending`, `accepted`, or `declined` state, and the match
carries a confirmed banner at the top of the thread.

## Who may respond

Only the **recipient** of a proposal may accept or decline it. The sender sees
"Waiting for the other person to respond." This is enforced twice:

- The chat bubble shows Accept/Decline only when
  `message.senderUid != currentUid` and the proposal is still pending.
- The database function `respond_to_viewing_proposal(match_id, message_id,
  status)` rejects an answer from the sender, from a non-participant, from a
  closed match, and from an already-answered proposal.

The owner is not privileged here. A renter-created proposal is accepted by the
owner, and an owner-created proposal is accepted by the renter.

## One transaction, not two writes

Accepting used to update the message and the match in two separate requests,
which could disagree if one failed. The current flow is:

1. The client calls `respond_to_viewing_proposal`.
2. That function updates the message in one transaction.
3. The `messages_apply_proposal_response` trigger updates the match's
   `viewingStatus` and `viewingDate` in the same transaction.
4. Realtime sends the new message and match to both accounts.

Creating a proposal is similarly one insert. The `messages_apply_to_match`
trigger increments `messagesCount`, writes `lastMessage`, and moves the match to
`proposed` with the chosen date.

## Local cache behavior

`DatabaseService.setSubdocument` merges partial rows into the local mirror. An
earlier version replaced the whole row, so accepting a proposal locally wiped
the message's `text`, `senderUid`, `type`, and `sentAt`, making the bubble
disappear until Realtime delivered the full row. Merging keeps the bubble
readable even when the connection is flaky.

## Client fallback

If `0006_chat_reliability_and_soft_delete.sql` has not been applied yet, the
repository falls back to the old two-write path so the feature still works. That
path is not atomic and is only a compatibility bridge; the RPC is the supported
implementation.
