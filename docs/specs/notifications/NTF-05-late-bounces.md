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

Most mail relays accept any well-formed address and only learn later that the client's mail
server refused it. Today that bounce stays in the email provider's dashboard, so the quote or
invoice says its email arrived when it didn't. Take in bounce reports from any provider through
one generic, signed endpoint, so a late bounce gets the same "Email not delivered" warning,
notification and Resend as a refusal at send time (QTE-04, PAY-02).

## User stories

- As an owner, I want to know when a quote's email bounced two minutes after it was sent, so I
  can fix the address and resend before the client wonders where it is.
- As an operator, I want to switch email providers without code changes.

## Acceptance criteria

- [ ] An inbound endpoint accepts bounce events signed with a shared secret from the
      environment (HMAC over a timestamp and the body). Unsigned, mis-signed, stale (over 5
      minutes) or oversized posts are refused, and the endpoint is "not found" with no secret.
- [ ] It understands a standard delivery status notification (per-recipient action, status code
      such as 5.1.1, diagnostic code) and our own strict, versioned event JSON (event id, type,
      Message-ID, reference, recipient, status code, time). Nothing names a provider; where a
      provider can't post this, a small forwarder kept in `infra/` (ADR 0026) translates it.
- [ ] Each event is processed once: a repeated post (same event id, or the same body when there's
      no id) does nothing, and an event for an email already marked undelivered changes nothing.
- [ ] Every client email carries an opaque per-email reference header. An event is matched by
      its Message-ID or that reference, and only if its recipient is one the email went to.
      Unmatched events (platform email, unknown ids) and events more than 14 days after the
      email was sent are dropped and counted, never stored.
- [ ] A matched permanent failure marks the email undelivered with the reason in plain words
      and the status code, using send time's rules: a mailbox status (5.1.x, 5.2.1) is "Address
      refused" and suppresses that address for the business and flags the client; any other
      permanent status is "Couldn't send" without blaming the address. Delays and temporary
      statuses change nothing.
- [ ] The existing undelivered path follows, unchanged: the "Email not delivered" warning with
      when, reason, code and Resend on the quote or invoice, the list badge, the client
      timeline entry, the team's "Client email not delivered" notification, and the send
      history's "Not delivered". The same once-only and superseded-send rules apply. If the
      client has already answered the quote or paid the invoice, the bounce is recorded in the
      send history and timeline only, with no warning or notification.
- [ ] A complaint (the client marked it as spam) blocks the address for that business and notes
      it on the client ("marked an email as spam"), with no team notification or Resend prompt.
- [ ] Privacy: only the event id, type, status code, a reason category, the time and the matched
      email are kept; the diagnostic text, addresses and raw payload are neither stored nor
      logged. Stored events are deleted after 90 days.
- [ ] Optional fallback, built only if the relay keeps our envelope sender: bounce emails to a
      signed per-email return address reach the app through the existing inbound-email path
      (signed post, stored, routed to their own mailbox), never copied to the human support
      inbox, and are parsed and processed as above. Off unless configured.
- [ ] Operators can see, without addresses, how many events arrived, matched or were dropped.
- [ ] Tests cover signatures and replay, both formats, idempotency, matching and recipient
      checks, the 14-day cut-off, statuses, complaints, CC'd emails, answered or paid documents,
      the warning and notification, tenancy, privacy (no address stored) and the fallback.

## Out of scope

- Delivered and opened events (NTF-01). Platform email's bounces. Provider-specific code.

## Decisions

- Spec late bounces, with an ADR for a generic bounce-event endpoint; plain SMTP stays for
  sending and no provider is named in code (owner, 2026-11-22). [ADR 0028](../../adr/0028-generic-bounce-event-endpoint.md).
- Our own signed, versioned event format, with a forwarder in `infra/` for providers that can't
  sign it; an opaque per-email reference header beside the Message-ID (owner, 2026-11-22).
- Complaints block the address for the business and are noted on the client; a bounce after the
  client answered or paid is recorded without a warning; events over 14 days old are ignored;
  the fallback mailbox only if the relay keeps our envelope sender (owner, 2026-11-22).

## Implementation notes

- Today's outcome comes only from the SMTP conversation: `ClientMailDeliveryJob` (`classify`,
  `RECIPIENT_STATUSES`) and `EmailMessage#mark!` → `announce_undelivered`, `problem_reason`,
  `reply_code`, `superseded?`; suppression is `EmailSuppression.suppress!`. The schema already
  has `delivered_at`, `complained_at` and a `complained` status.
- Message-IDs are ours (`ApplicationMailer`, a UUID on the sending domain), stored without
  brackets in `email_messages.provider_message_id` (unique) by `ClientMailer`. A lookup by it
  spans businesses, so it needs `Tenancy.across_businesses(reason:)` and a reviewer's eye.
- Warning and badges: `admin/sends/_delivery_warning`, `admin/quotes/_list_flags`,
  `admin/invoices/_results`, `admin/clients/_timeline_events`; type `email_not_delivered`
  (`NotificationType`). Tests to extend: `test/integration/admin/quote_delivery_test.rb`.
- Precedents: signed ingress `InboundEmailIngress` + `Inbound::SupportEmailsController`
  (docs/runbooks/inbound-email.md); store-once, process-later `ConnectEvent` (90 days, fields
  only). `SupportMail` already drops bounces sent to support; `ApplicationMailbox` routes all mail
  to support, so the fallback needs its own route and recipient.

## Open questions

- None. The owner answered them on 2026-11-22.
