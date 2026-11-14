---
id: PLT-12
title: Client links
domain: platform
milestone: M1
depends_on: [PLT-06, PLT-08]
---
# PLT-12 · Client links

> Requirements: [01-platform](../../plans/01-platform.md) R12; vision principle 2

## Summary

Clients never create accounts. Every client interaction — viewing a quote, approving it,
seeing a visit, paying an invoice — happens through a secure link. Build that mechanism once so
quotes, visits and invoices all share the same security, branding and expiry behavior.

## User stories

- As a client, I want to open a link from an email or text and immediately see my document on
  my phone, with no sign-in.
- As an owner, I want to revoke a link I sent to the wrong person.
- As the operator, I want links to be impossible to guess or enumerate.

## Acceptance criteria

- [ ] A link grants access to exactly one document (and the actions allowed on it), for one
      business; it never grants access to anything else.
- [ ] Links are long, random, unguessable, and not derived from record IDs; lookup is
      constant-time-safe and rate limited.
- [ ] Links have an expiry policy per document type (e.g. long-lived for invoices until paid;
      quotes until a set time after expiry) and can be revoked and re-issued by staff.
- [ ] Opening a link renders inside the client-facing layout with the business's branding and
      no staff navigation; client pages are excluded from search indexing.
- [ ] Each view is recorded (time, coarse device info) for "viewed" status; staff previews
      ("view as client") do not count as client views.
- [ ] Expired, revoked or suspended-business links show a friendly page with the business's
      contact details and a way to request a fresh link.
- [ ] Sensitive actions taken via a link (approve, pay) are protected against forgery/replay.
- [ ] Tests cover expiry, revocation, cross-tenant isolation and staff-preview behavior.

## Out of scope

- Specific document pages (QTE-03, JOB-05, PAY-02). A client hub listing all documents (backlog).

## Open questions

- ~~Should links copied for SMS require a short verification?~~ Resolved: no verification at
  launch (ADR 0016).
- Default expiry per document type: the mechanism lets each document set its own
  (`client_link_expires_at`), with 90 days as the fallback. QTE-03 and PAY-02 pick their values.
