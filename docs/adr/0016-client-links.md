# 0016. One client-link mechanism, with derived tokens and per-link state

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-12; used by QTE-03, JOB-05, PAY-02 and anything else clients open

## Context

Clients never have accounts (vision principle 2). Quotes, visits and invoices all need the same
things: an unguessable URL, expiry, revoke and re-issue, view tracking, a branded page and safe
one-time actions. ADR 0013 sketched a `public_token` column on each document. That can't be
revoked or re-issued without changing the document, and it has nowhere to record views.

## Decision

- **A `client_links` row per link**, pointing at one document (polymorphic) in one business,
  with the actions it allows (`approve`, `decline`, `pay`, `request_changes`), `expires_at`,
  `revoked_at`, view counters and events. This replaces the per-document `public_token` idea
  from ADR 0013.
- **Tokens are derived, not stored:** `base58(HMAC-SHA256(secret_key_base, link.secret))`,
  32 characters (about 187 bits). Lookups match on the token's SHA-256 digest, so tokens are
  never compared directly and a database copy alone can't produce working links. Staff can
  always rebuild the URL to resend it. Rotating `secret_key_base` invalidates every link; that
  is acceptable, and recorded here.
- **Expiry is per document type:** the document defines `client_link_expires_at`, otherwise 90
  days. Re-issuing creates a new link and revokes the old one.
- **Client pages:**
  - Every client controller includes `ClientLinkAccess`. It resolves the link (the only
    cross-business lookup), sets `Current.business`, refuses inactive links with a friendly
    page (business contact details and "request a new link"), sends `noindex` and
    `Referrer-Policy: no-referrer` (amended to `same-origin` by
    [ADR 0018](0018-client-page-referrer-policy.md)), and rate-limits by IP.
  - Staff "preview" renders the same page with a banner and records no view.
- **One-time actions** (`perform_once!`) write a uniquely indexed event in the same
  transaction as the action. A replayed or double-submitted approve or pay does nothing.
  Forms still carry Rails CSRF tokens.
- **No extra verification at launch** (such as the last four digits of a phone number) for
  links opened from SMS. Revisit if links are forwarded in practice.

## Consequences

- Documents add `client_link_partial` and `client_link_expires_at` and get links for free.
- "Viewed" status comes from `first_viewed_at` and `views_count`.
- Rotating `secret_key_base` needs a plan to re-issue open links: lookups re-derive the token
  and reject old URLs. The runbook (PLT-09) records this.
- Tokens sit in URL paths. The Rails request log redacts them (`SecretPathLogger`) and
  controller logs filter `:token`. No proxy in front of the app logs paths on the VMs (ADR 0023);
  Cloudflare sees them at its edge, so its URL-logging features stay off (PLT-09/PLT-10).
- **Cost:** none.
