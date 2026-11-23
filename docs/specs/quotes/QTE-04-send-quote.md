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

- [x] From a draft, Owners/Admins choose "Send by email" (recipient defaults to client email,
      editable; optional CC; subject and personal message prefilled and editable) or "Copy link"
      (marks the quote as sent).
- [x] The email uses the business-branded layout (NTF-01), shows a summary (total, expiry) and a
      prominent "View quote" button to the client link, with the PDF attached.
- [x] Sending requires a confirmed user account (ACC-01) and a valid recipient; errors are clear.
- [x] On send, the quote's content is frozen as a sent revision, status becomes Sent, and the
      send is recorded (who, when, channel, recipient). *Frozen: a sent quote is read-only;
      numbered revisions come with QTE-06.*
- [x] A billable "quote sent" usage event is recorded exactly once per quote (first send), for
      BIL-02 to count.
- [x] Delivery problems (bounce) are surfaced on the quote. *Those the mail server reports
      while sending (ADR 0017): on the quote and in the quotes list. Later bounces aren't
      captured yet (see Implementation notes).*
- [x] Resending an unchanged quote doesn't create a new revision or usage event.
- [x] Tests cover send paths, freezing, usage recording, unconfirmed users and tenancy.

## Out of scope

- Revisions after sending (QTE-06). SMS sending by Shadetree (backlog). Follow-up reminders
  (backlog). Limit enforcement (BIL-03).

## Implementation notes

- **Undelivered email (QA #274).** When the latest email of a quote still waiting on the client
  was refused or couldn't be sent, the page leads with an "Email not delivered" warning: the
  address, when, the reason in plain words, the mail server's code ("554 5.7.1"), and Resend
  (the usual send page, `office` permission). The quotes list and the client's timeline show an
  "Email not delivered" badge; the team gets an "email not delivered" notification (NTF-02).
  The Revisions list shows each send and whether its email arrived. Invoices do the same.
  A link copied since replaces the warning with a quiet note; an expired quote isn't warned
  about (it's renewed with a revision, QTE-06). Only the document's latest email (or one not
  tied to a send, like an automation's) is announced, once; a failure on Shadetree's side (no
  receiving server's reply, rejected credentials) is reported to operators, not to the team.
- **What's known:** only what the SMTP conversation says while the delivery job sends (ADR
  0017). Bounces after the relay accepts an email stay in the provider's dashboard; NTF-05
  captures them through a generic, signed bounce-event endpoint ([ADR 0028](../../adr/0028-generic-bounce-event-endpoint.md)).

## Decisions

- Owner, 2026-11-21: an undelivered email doesn't change the status. The quote stays Sent (its
  link still works), with the warning, the reason and Resend. An approval of a later revision
  still counts; where that revision's own email didn't arrive, the response says so quietly.
- #289, 2026-11-21: a first send of a quote or invoice whose total is $0.00 asks first ("Send it at
  $0.00"); lines without a price are named on the send page either way. An approved quote can be
  sent again as a copy: it stays approved, never counts toward usage, and has its own wording.

## Open questions

- ~~Should sending via "copy link" count toward usage?~~ Yes: the first send counts, by any channel.
- ~~Does a revision re-sent after changes count as a new usage event?~~ No: one event per quote
  (`usage_events` is unique per subject).
