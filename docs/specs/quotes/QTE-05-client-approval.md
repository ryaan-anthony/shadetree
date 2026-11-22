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

- [x] On an open (sent, unexpired, not superseded) quote, the client can Approve, Decline or
      Request changes.
- [x] Approve requires typing a full name and confirming acceptance of the terms; on submit, the
      quote becomes Approved and records signer name, timestamp, IP, user agent and an
      immutable snapshot/version reference of exactly what was approved. *A JSON snapshot of
      the lines, prices, taxes, totals and terms, its SHA-256 digest, and the quote's version.*
- [x] Decline records an optional reason; Request changes records a required message; both
      update status and keep the quote viewable.
- [x] After approval the client sees a confirmation with next steps (configurable short text in
      settings) and can download the approved PDF (showing signer and date).
- [x] The business is notified on approve, decline and change request (email now; in-app via
      NTF-02); the client receives an approval confirmation email. *Email goes to each active,
      confirmed Owner and Admin. The client's confirmation goes to the email they gave when
      approving, or the one on file.*
- [x] Owners/Admins can mark a quote approved on the client's behalf (e.g. verbal approval),
      recording who did it and a required note. *Also after a change request; not on an
      expired quote. No client email is sent for these.*
- [x] Double submissions and stale pages are handled (no duplicate approvals; approving a
      superseded revision is refused with a link to the latest). *A superseded revision's page
      shows the latest at the same link; an answer posted from it fails the version check.*
- [x] Approved quotes are locked from editing.
- [x] Tests cover each action, evidence capture, idempotency, expiry and link scope.

## Out of scope

- Converting to a job (JOB-01). Deposits and self-scheduling after approval (backlog).
- Drawn signatures (backlog).

## Implementation notes

- The client's IP address is stored with the response, part of its signed evidence, and in the
  "Quote responses" CSV (INS-02), but shown on no page: staff see the device ("Phone · Safari").
  *Owner decision, 2026-11-21 (QA #274).* The operator audit log (operators' own IPs) and a
  user's own session list are unaffected.
- #289: on the staff quote page the approval reference sits behind a "Reference" disclosure and
  the quote version isn't shown (both stay in the record and the export); a record that doesn't
  verify still says so up front.

## Open questions

- ~~Should the client be able to approve and request changes at once?~~ No: approve, decline
  and request changes are separate actions.
- ~~Is collecting the client's email at approval (when the quote was sent via link only)
  useful?~~ Yes: an optional email field for the receipt when there's no email on file.
