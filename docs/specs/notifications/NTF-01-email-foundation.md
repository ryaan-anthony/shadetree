---
id: NTF-01
title: Transactional email foundation
domain: notifications
milestone: M2
depends_on: [CAT-02, PLT-09]
---
# NTF-01 · Transactional email foundation

> Requirements: [08-notifications](../../plans/08-notifications.md) R1–R6, R10

## Summary

Quotes, visits and invoices all travel by email, and a lost or spam-foldered email is a lost
job. Build the shared foundation every client-facing email uses: authenticated sending,
business branding, reply-to the business, delivery tracking and bounce handling.

## User stories

- As an owner, I want emails to my clients to come from my business name and replies to reach
  my inbox.
- As an owner, I want to know if an email to a client bounced so that I can fix the address.
- As a developer, I want one way to send a branded client email with tracking.

## Acceptance criteria

- [ ] Client-facing emails send from a platform sending domain with SPF, DKIM and DMARC
      configured, using "<Business name> via Shadetree"-style display names and the business's
      email as reply-to.
- [ ] A shared branded layout (logo, brand color, business contact footer, plain-text part) is
      used by all client-facing emails; it renders well in major clients and dark mode.
- [ ] Every outbound email is recorded per business with type, recipient, related record, time
      and delivery outcome updated from provider events (delivered, bounced, complained).
- [ ] Hard bounces/complaints suppress further sends to that address for that business and
      flag the client record; staff can clear the flag after fixing the address.
- [ ] Sending is asynchronous with retries; failures are visible on the related record.
- [ ] Staging cannot email real clients (sandbox or allow-list).
- [ ] The message catalog in 08-notifications is kept in a single place in the app; previews of
      each message are available in development.
- [ ] Platform emails (auth, invitations) use a Shadetree-branded variant of the layout.
- [ ] Tests cover layout rendering, reply-to, suppression and event processing.

## Out of scope

- Team in-app notifications (NTF-02). SMS, editable templates, per-business sending domains
  (backlog).

## Open questions

- Provider choice (cost at free-tier volume, event webhooks) — ADR. Domain depends on G8.
- Track opens? Recommend no (privacy, unreliable); use client-link views instead.
