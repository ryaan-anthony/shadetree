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
- [ ] It understands a standard delivery status notification (the per-recipient action, status
      code such as 5.1.1, and diagnostic code) and a small, documented, provider-neutral event
      JSON (event id, type, Message-ID, recipient, status code, time). Nothing names a provider.
- [ ] Each event is processed once: a repeated post (same event id, or the same body when there's
      no id) does nothing, and an event for an email already marked undelivered changes nothing.
- [ ] An event is matched to the client email by its Message-ID, and only if the recipient it
      names is one the email went to. Unmatched events (platform email, unknown ids) are dropped
      and counted, never stored.
- [ ] A matched permanent failure marks the email undelivered with the reason in plain words
      and the status code, using send time's rules: a mailbox status (5.1.x, 5.2.1) is "Address
      refused" and suppresses that address for the business and flags the client; any other
      permanent status is "Couldn't send" without blaming the address. Delays and temporary
      statuses change nothing.
- [ ] The existing undelivered path follows, unchanged: the "Email not delivered" warning with
      when, reason, code and Resend on the quote or invoice, the list badge, the client
      timeline entry, the team's "Client email not delivered" notification, and the send
      history's "Not delivered". The same once-only and superseded-send rules apply.
- [ ] Privacy: only the event id, type, status code, a reason category, the time and the matched
      email are kept; the diagnostic text, addresses and raw payload are neither stored nor
      logged. Stored events are deleted after 90 days.
- [ ] Optional fallback: bounce emails sent to a bounce address reach the app through the
      existing inbound-email path (signed post, stored, routed to their own mailbox), are parsed
      as delivery status notifications and processed as above. Off unless configured.
- [ ] Operators can see, without addresses, how many events arrived, matched or were dropped.
- [ ] Tests cover signatures and replay, both formats, idempotency, matching and recipient
      checks, mailbox versus other statuses, CC'd emails, the warning and notification, tenancy,
      privacy (no address in logs or rows) and the fallback mailbox.

## Out of scope

- Delivered and opened events (NTF-01). Platform email's bounces. Provider-specific code.

## Decisions

- Spec late bounces, with an ADR for a generic bounce-event endpoint; plain SMTP stays for
  sending and no provider is named in code (owner, 2026-11-22). [ADR 0028](../../adr/0028-generic-bounce-event-endpoint.md).

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

- **(blocking)** How events reach the endpoint. Recommend our own signing contract and one
  strict, versioned JSON shape (not guessing each provider's keys), with a small forwarder in
  `infra/` (ADR 0026) translating where a provider can't sign that way, so the app stays neutral.
- Complaints (marked as spam). Recommend accepting them: suppress the address for the business,
  note it on the client ("marked an email as spam"), no team notification or Resend prompt.
- A bounce after the client has already answered or paid. Recommend recording it in the send
  history and timeline, without the warning or the notification: the client got there anyway.
- Late events. Recommend ignoring events more than 14 days after the email was sent.
- Matching if a relay rewrites the Message-ID. Recommend also sending an opaque per-email
  reference header and matching on either.
- Fallback. Recommend building it only if the relay keeps our envelope sender, using a signed
  per-email return address (as support's reply addresses), and never copying it to the human
  support inbox.
