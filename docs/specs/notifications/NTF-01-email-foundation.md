---
id: NTF-01
title: Transactional email foundation
domain: notifications
milestone: M2
depends_on: [CAT-02]
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
      email as reply-to. *In place: sending from `getshadetree.com` over SMTP, the display name
      and reply-to. Still to do: the provider's DNS records (ADR 0017).*
- [x] A shared branded layout (logo, brand color, business contact footer, plain-text part) is
      used by all client-facing emails; it renders well in major clients and dark mode.
- [x] Every outbound email is recorded per business with type, recipient, related record, time
      and delivery outcome. *Outcome as the SMTP server reports it (sent, refused, failed); later
      bounces and complaints stay in the provider's dashboard (ADR 0017).*
- [x] Addresses the mail server refuses suppress further sends to that address for that business
      and flag the client record; staff can clear the flag after fixing the address.
- [x] Sending is asynchronous with retries; failures are visible on the related record.
- [ ] Staging cannot email real clients (sandbox or allow-list). *Decided: staging gets the
      provider's sandbox SMTP credentials, which only deliver to authorized recipients. Ticked
      once the staging deploy sets them (PLT-09).*
- [x] The message catalog in 08-notifications is kept in a single place in the app; previews of
      each message are available in development.
- [x] Platform emails (auth, invitations) use a Shadetree-branded variant of the layout.
- [x] Tests cover layout rendering, reply-to, suppression and SMTP failure handling.

## Out of scope

- Team in-app notifications (NTF-02). SMS, editable templates, per-business sending domains
  (backlog).

## Open questions

- ~~Provider choice (cost at free-tier volume, event webhooks) — ADR.~~ Resolved: the product
  owner's provider over plain SMTP, with no provider integration (ADR 0017). In development,
  letter_opener_web opens every email in the browser at `/letter_opener`.
- ~~Sending domain?~~ Resolved: the root domain `getshadetree.com` (G8). Its DNS records are listed
  in ADR 0017.
- ~~Staging sandbox?~~ Resolved: the provider's sandbox SMTP credentials on staging.
- ~~Track opens?~~ Resolved: no (privacy, unreliable); client-link views (PLT-12) are the signal.
