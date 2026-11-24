---
id: NTF-05
title: Late bounces
domain: notifications
milestone: M6
depends_on: [NTF-01, NTF-02, QTE-04, PAY-02, OPS-05]
---
# NTF-05 · Late bounces

> Requirements: [08-notifications](../../plans/08-notifications.md) R3–R5

## Summary

Relays accept any well-formed address and learn later that the client's server refused it, so a
quote or invoice can look delivered when it wasn't. Take in bounce and complaint reports through
one generic, signed endpoint (ADR 0028), so a late bounce is handled like a send-time refusal.

## User stories

- As an owner, I want to know a quote's email bounced after it was sent, so I can fix and resend.
- As an operator, I want to switch email providers without code changes.

## Acceptance criteria

- [x] `POST /inbound/email_events` takes `X-Shadetree-Timestamp` and `X-Shadetree-Signature`
      (`v1=` HMAC-SHA256 over `<timestamp>.<body>`), keyed by a per-environment secret from ENV.
      Bad signatures, timestamps over 5 minutes off and bodies over 256 KB are refused; failed
      attempts are rate limited per IP; no secret means "not found" (as the support ingress).
- [x] It reads a standard delivery status notification and our own strict, versioned JSON
      (event id, type, Message-ID, reference, recipient, status and reply codes, time), documented
      in a runbook. No provider is named in app code. The forwarder in `infra/` for a provider
      that can't post this is deferred (owner, 2026-11-24): late bounces stay unhandled until
      a relay can post our format.
- [x] Matching and the recipient check happen in the request. An event matches a client email by
      Message-ID or by the reference header it already carries, and only if its recipient is the
      email's To or a CC of its send. Unmatched events, events for a matched email more than 14
      days after it was sent, delays and temporary statuses are counted and nothing is stored.
- [x] Only then is the event stored, once (event id, else a body digest; a repeat does nothing):
      type, status code, reason category, time, the email and the recipient's role (To or CC).
      Never the address, diagnostic text or payload, in rows or logs. It's processed in the
      background; rows go after 90 days.
- [x] To bounces: a mailbox status (5.1.x, 5.2.1) marks the email "Address refused" and blocks
      the address for the business; any other permanent status marks it "Couldn't send" without
      blaming it. The error is send time's words with the codes ("The mail server refused this
      address (550 5.1.1)", "… refused the email (5.7.1)"); a late event is never our side.
- [x] Then the existing path: warning (when, reason, code, Resend), list badge, timeline, the
      "Client email not delivered" notification, send history; once-only and superseded rules.
- [x] No warning or notification, only the send history and timeline, when the quote has been
      approved, declined or had changes requested, or the invoice is paid in full or void, or the
      email is a receipt, visit or other non-document email.
- [x] A CC bounce blocks only that CC address for the business and is recorded in the send
      history; the email stays delivered, with no warning.
- [x] A complaint (marked as spam) blocks the address for the business, marks the email "Marked
      as spam" and adds "Marked an email as spam" to the client's timeline; no notification or
      Resend prompt. A complaint without a recipient matches on the reference and uses the To.
- [x] The ops console home has an "Email events" card: received, matched, dropped, last 7 days.
- [ ] Optional fallback, only if the relay keeps our envelope sender: bounce emails to a signed
      per-email return address arrive through the inbound-email path, parsed and processed as
      above, never copied to the human support inbox. Off unless configured. Not built: the
      relay in `infra/` doesn't keep our envelope sender.
- [x] Tests cover signatures, replay, limits, both formats, matching, the 14 days, each status,
      CCs, complaints, answered or paid, tenancy, no stored or logged address (no fallback built).

## Out of scope

- Delivered and opened events (NTF-01). Platform email's bounces. The relay's own suppression
  list: it still drops an address staff clear in the app; the runbook says to clear it there too.

## Decisions

- Spec late bounces with an ADR for a generic endpoint; plain SMTP stays and no provider is named
  in code (owner, 2026-11-22). [ADR 0028](../../adr/0028-generic-bounce-event-endpoint.md).
- Our own signed, versioned format with a forwarder in `infra/`; a per-email reference header;
  no warning once the client answered or paid; the fallback only if the relay keeps our envelope
  sender (owner, 2026-11-22).
- A bounced CC blocks only that address, recorded, no warning; a complaint blocks the address and
  goes on the timeline, no notification or Resend; events over 14 days after the email was sent
  are ignored (owner, 2026-11-23).
- Matching in the request, stored fields, 256 KB, rate limits, 90 days (follows the support
  ingress and `ConnectEvent`); the card (follows Background jobs; 7 days for the owner to confirm).
- The forwarder is deferred: ship the generic endpoint and runbook only; late bounces stay
  unhandled until a relay can post our format (owner, 2026-11-24).
- Only mailbox statuses and complaints block a CC; other permanent bounces are recorded in the
  send history only. A void invoice is treated as paid: send history and timeline only, no
  warning or notification (owner, 2026-11-24).

## Implementation notes

- Built: `EmailEventIngress` (verify, both formats), `Inbound::EmailEventsController`, `EmailEvent`
  (match, store, `process!` via `ProcessEmailEventJob`; `PruneEmailEventsJob`), `EmailEventTally`;
  `EMAIL_EVENTS_SECRET`; [runbook](../../runbooks/email-events.md). No fallback: the relay's
  config in `infra/` sets a custom MAIL FROM domain whose MX is the relay's own.
- A CC is stored by its position on the send; its problem shows in the send history.
- Dev seeds: a sent invoice whose email and CC bounced late, a paid one marked as spam, and the
  ops card's counts.

## Open questions

- None. The owner answered them on 2026-11-22 and 2026-11-23.
