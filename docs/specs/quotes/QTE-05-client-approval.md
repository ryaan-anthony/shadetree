---
id: QTE-05
title: Client approve / decline / request changes
domain: quotes
milestone: M2
depends_on: [QTE-03, NTF-01]
---
# QTE-05 · Client approve / decline / request changes

> Requirements: [05-quotes](../../plans/05-quotes.md) R11, R12, R13, R17

## Summary

The client says yes in one tap. From the quote page, a client approves (typing their name as a
signature and accepting terms), declines with an optional reason, or asks for changes. Every
response is recorded with strong evidence and the business is told immediately.

## User stories

- As a homeowner, I want to approve the quote from my phone in seconds.
- As a client, I want to ask for a change ("can you skip the side yard?") without a phone call.
- As an owner, I want proof of exactly what the client approved and when.

## Acceptance criteria

- [ ] On an open (sent, unexpired, not superseded) quote, the client can Approve, Decline or
      Request changes.
- [ ] Approve requires typing a full name and confirming acceptance of the terms; on submit, the
      quote becomes Approved and records signer name, timestamp, IP, user agent and an
      immutable snapshot/version reference of exactly what was approved.
- [ ] Decline records an optional reason; Request changes records a required message; both
      update status and keep the quote viewable.
- [ ] After approval the client sees a confirmation with next steps (configurable short text in
      settings) and can download the approved PDF (showing signer and date).
- [ ] The business is notified on approve, decline and change request (email now; in-app via
      NTF-02); the client receives an approval confirmation email.
- [ ] Owners/Admins can mark a quote approved on the client's behalf (e.g. verbal approval),
      recording who did it and a required note.
- [ ] Double submissions and stale pages are handled (no duplicate approvals; approving a
      superseded revision is refused with a link to the latest).
- [ ] Approved quotes are locked from editing.
- [ ] Tests cover each action, evidence capture, idempotency, expiry and link scope.

## Out of scope

- Converting to a job (JOB-01). Deposits and self-scheduling after approval (backlog).
- Drawn signatures (backlog).

## Open questions

- Should the client be able to approve and request changes at once? Recommend no.
- Is collecting the client's email at approval (when the quote was sent via link only) useful?
  Recommend optional email field for receipts.
