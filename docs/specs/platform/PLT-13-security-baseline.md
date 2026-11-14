---
id: PLT-13
title: Security baseline
domain: platform
milestone: M5
depends_on: [PLT-05, PLT-10]
---
# PLT-13 · Security baseline

> Requirements: [01-platform](../../plans/01-platform.md) R21, R22

## Summary

Before we take money and open sign-ups publicly, harden the application against the common
attacks a small SaaS faces: credential stuffing, form spam, cross-site scripting, and abuse of
public endpoints. Run a focused review and fix what it finds.

## User stories

- As a business owner, I want my account protected from password-guessing attacks.
- As the operator, I want public forms (sign-up, contact, request form) to resist spam bots so
  that our sending domain isn't burned.
- As a client, I want confidence that the payment page is legitimate and secure.

## Acceptance criteria

- [ ] A strict content security policy is enforced (no inline scripts/styles except via
      nonces), along with secure headers (HSTS, frame protections, referrer policy).
- [ ] Rate limiting applies to sign-in, password reset, sign-up, client-link lookup, request
      form and contact form, with sensible limits and friendly error pages.
- [ ] Public forms have invisible bot protection (e.g. honeypot + timing) with an escalation
      option if abuse is detected.
- [ ] Uploaded files are validated by content type and size, served safely (no execution, no
      inline rendering of risky types), and stripped of location metadata for photos.
- [ ] Session cookies are secure, HTTP-only and same-site; session fixation is prevented.
- [ ] A security review checklist (authentication, authorization, tenancy, uploads, links,
      payments webhooks, mass assignment, SSRF) is completed and findings resolved or ticketed.
- [ ] A responsible disclosure page/contact exists (security.txt).

## Out of scope

- External penetration test (recommended after launch). 2FA for business users (backlog).

## Open questions

- Is a third-party bot challenge acceptable on the public request form if abuse appears?
  Privacy and UX trade-off.
