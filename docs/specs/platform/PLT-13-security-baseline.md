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
- [x] Rate limiting applies to sign-in, password reset, sign-up, client-link lookup, request
      form and contact form, with sensible limits and friendly error pages.
- [x] Public forms have invisible bot protection (e.g. honeypot + timing) with an escalation
      option if abuse is detected.
- [x] Uploaded files are validated by content type and size, served safely (no execution, no
      inline rendering of risky types), and stripped of location metadata for photos.
- [x] Session cookies are secure, HTTP-only and same-site; session fixation is prevented.
- [x] A security review checklist (authentication, authorization, tenancy, uploads, links,
      payments webhooks, mass assignment, SSRF) is completed and findings resolved or ticketed.
- [x] A responsible disclosure page/contact exists (security.txt).

## Out of scope

- External penetration test (recommended after launch). 2FA for business users (backlog).

## Decisions

- **No third-party bot challenge for now** (owner accepted the recommendation, M5 planning):
  honeypot and timing first; the escalation is a lockdown that tightens both, and a challenge
  is revisited only if abuse gets past that.
- **Style attributes are gone, not allowed.** `style-src` has no `'unsafe-inline'`; values known
  only at render time become classes backed by one nonced `<style>` (`InlineStyleHelper`).
  JavaScript still sets styles through the CSSOM (`el.style.x = …`), which CSP allows.
- **One random nonce per session, not per response**, kept in the session from the first
  response, so `<style>` blocks in Turbo navigations, frames and streams match the page they land
  in (a per-response nonce would make Turbo reload every page). Signing in starts a new one and
  signing out resets the session; those forms skip Turbo, and a `csp-nonce-check` meta tracked
  by Turbo forces a full load if the nonce changes some other way.
- **Third parties are added one at a time** in the policy when a feature needs them: Stripe's
  hosted checkout (BIL-04) will need `form-action` once we post to it. Self-hosted Plausible
  (MKT-04) is in: its host joins `script-src` and `connect-src` only when analytics is on.

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

Part 2 (abuse, uploads, review):
- `AbuseProtection` (in every controller): `too_many_requests` (friendly page with the real
  wait and `Retry-After`; `public/429.html` as a safety net), the hidden field and a signed,
  single-use form token that must be a few seconds old (a re-shown form keeps its start time),
  per-IP attempts, logged rejections (`[abuse]`), and the lockdown (`bin/rails
  security:lockdown HOURS=`, or `FORMS_LOCKDOWN=true`: 10-second wait, 5 tries per IP per 15
  minutes; kept in the cache). Sign-up, the request form and the contact form use it (MKT-02
  rebuilds the contact form so it keeps what's sent).
- Scripts and stylesheets join HTML/SVG/XML in being served as plain-byte downloads.
- Invitation lookups now count toward the rate limit.
- The review and its findings: [docs/security/review-checklist.md](../../security/review-checklist.md).
