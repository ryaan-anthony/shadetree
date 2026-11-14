---
id: QTE-04
title: Send quote
domain: quotes
milestone: M2
depends_on: [QTE-02, QTE-03, NTF-01]
---
# QTE-04 · Send quote

> Requirements: [05-quotes](../../plans/05-quotes.md) R7, R8, R9

## Summary

Get the quote in front of the client the way they'll actually read it: an email with a clear
button to the quote page and the PDF attached, or a copyable link for the owner to text from
their own phone. This is the moment that counts toward plan usage.

## User stories

- As an owner, I want to send a quote by email with a short personal note so that it feels
  personal, not automated.
- As an owner whose client prefers texts, I want to copy the link and send it from my phone.
- As an owner, I want to know the quote was delivered.

## Acceptance criteria

- [ ] From a draft, Owners/Admins choose "Send by email" (recipient defaults to client email,
      editable; optional CC; subject and personal message prefilled and editable) or "Copy link"
      (marks the quote as sent).
- [ ] The email uses the business-branded layout (NTF-01), shows a summary (total, expiry) and a
      prominent "View quote" button to the client link, with the PDF attached.
- [ ] Sending requires a confirmed user account (ACC-01) and a valid recipient; errors are clear.
- [ ] On send, the quote's content is frozen as a sent revision, status becomes Sent, and the
      send is recorded (who, when, channel, recipient).
- [ ] A billable "quote sent" usage event is recorded exactly once per quote (first send), for
      BIL-02 to count.
- [ ] Delivery problems (bounce) are surfaced on the quote.
- [ ] Resending an unchanged quote doesn't create a new revision or usage event.
- [ ] Tests cover send paths, freezing, usage recording, unconfirmed users and tenancy.

## Out of scope

- Revisions after sending (QTE-06). SMS sending by Shadetree (backlog). Follow-up reminders
  (backlog). Limit enforcement (BIL-03).

## Open questions

- Should sending via "copy link" count toward usage? Recommend yes (same value delivered).
- Does a revision re-sent after changes count as a new usage event? Recommend no.
