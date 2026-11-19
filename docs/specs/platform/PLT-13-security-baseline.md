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

- [x] A strict content security policy is enforced (no inline scripts/styles except via
      nonces), along with secure headers (HSTS, frame protections, referrer policy).
- [ ] Rate limiting applies to sign-in, password reset, sign-up, client-link lookup, request
      form and contact form, with sensible limits and friendly error pages.
- [ ] Public forms have invisible bot protection (e.g. honeypot + timing) with an escalation
      option if abuse is detected.
- [ ] Uploaded files are validated by content type and size, served safely (no execution, no
      inline rendering of risky types), and stripped of location metadata for photos.
- [x] Session cookies are secure, HTTP-only and same-site; session fixation is prevented.
- [ ] A security review checklist (authentication, authorization, tenancy, uploads, links,
      payments webhooks, mass assignment, SSRF) is completed and findings resolved or ticketed.
- [x] A responsible disclosure page/contact exists (security.txt).

## Out of scope

- External penetration test (recommended after launch). 2FA for business users (backlog).

## Decisions

- **No third-party bot challenge for now** (owner accepted the recommendation, M5 planning):
  honeypot and timing first; a challenge is revisited only if abuse gets past them.
- **Style attributes are gone, not allowed.** `style-src` has no `'unsafe-inline'`; values known
  only at render time become classes backed by one nonced `<style>` (`InlineStyleHelper`).
  JavaScript still sets styles through the CSSOM (`el.style.x = …`), which CSP allows.
- **One random nonce per session, not per response**, kept in the session from the first
  response, so `<style>` blocks in Turbo navigations, frames and streams match the page they land
  in (a per-response nonce would make Turbo reload every page). Signing in starts a new one and
  signing out resets the session; those forms skip Turbo, and a `csp-nonce-check` meta tracked
  by Turbo forces a full load if the nonce changes some other way.
- **Third parties are added one at a time** in the policy when a feature needs them: Stripe's
  hosted checkout (BIL-04) will need `form-action` once we post to it; self-hosted Plausible
  (MKT-04) its script and connect origin.

## Implementation notes

Part 1 (headers, policy, cookies, disclosure):
- `config/initializers/content_security_policy.rb`: `default-src 'self'`, scripts and styles
  `'self'` plus nonce, `frame-ancestors 'none'`, `form-action 'self'`, `object-src 'none'`,
  `base-uri 'self'`, reports to `/csp-reports` (`CspReportsController`: logged as paths with
  tokens masked, truncated, rate limited, never stored).
- `config/initializers/secure_headers.rb`: `Cross-Origin-Opener-Policy: same-origin`,
  `Permissions-Policy` turning off camera, microphone, geolocation, USB, payment and sensors,
  referrer policy; the session cookie is HTTP-only, `SameSite=Lax`, secure in production. HSTS
  comes from `force_ssl`; Devise renews the session id at sign-in (tested).
- Inline scripts on the old marketing nav and pricing page became Stimulus controllers
  (`menu`, `billing_toggle`); the style guide's demo form uses `styleguide_demo`.
- `public/.well-known/security.txt` (security@getshadetree.com, expires 2027-11-18; a test
  fails 60 days before so it gets renewed).
- `SecurityHeadersTest` renders public, signed-in and client pages and fails on any style
  attribute, inline handler, `javascript:` link, or inline script/style without the nonce; it
  also scans every view and script for them, and checks that a view calling `inline_style`
  emits its `<style>`.
