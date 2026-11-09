# Structured Viewing Proposals Inside Real-Time Chat

Rather than relying entirely on free-form text messages where critical dates and inspection times get lost or disputed, Rently introduces an interactive `Viewing Proposal` message type directly in the 1-on-1 Firestore chat. A Student or Landlord can propose an in-person dorm inspection by selecting a date and time slot. This renders as a distinct, actionable UI card within `matches/{matchId}/messages/{msgId}` with `pending`, `accepted`, or `declined` states, automatically updating an active inspection banner at the top of the chat thread.
