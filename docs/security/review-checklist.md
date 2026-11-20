# Security review checklist

> PLT-13. Run through this before launch and again whenever a feature adds a public endpoint,
> an upload, an outbound request or a webhook. Record the date, who ran it and what was found.

## Review: 2026-11-18 (PLT-13, before billing and public sign-up)

Status: **✓** checked and fine · **fixed** found and fixed in PLT-13 · **ticketed** carried by
the issue named.

### Authentication

- ✓ Devise: passwords 10–128 characters, bcrypt cost 12, paranoid mode (no "no such account"),
  lockout after 10 failures (unlock by email or after time), reset links valid 6 hours,
  remember-me cleared on sign-out.
- ✓ Session cookie HTTP-only, `SameSite=Lax`, secure in production; id renewed at sign-in.
- ✓ Rate limits per IP: sign-in, password reset, confirmation and unlock emails.
- fixed — sign-up had a per-IP limit but no bot check: now the hidden field and form timing.
- pending #194 — operators (OPS-01, not merged yet): two-factor with attempt limits and
  lockout, idle timeout, fresh code for access changes. Re-check once merged.
- ✓ CSRF protection on every form (Rails defaults); the only API controller is the CSP report
  endpoint, which changes nothing.
- ticketed — two-factor for business users: backlog (spec out of scope).

### Authorization and tenancy

- ✓ Every staff action declares a permission; undeclared actions are denied (ACC-04,
  `Authorization`), and checks use permissions, never role names.
- ✓ Tenant data is scoped by default (`BusinessOwned`, ADR 0014); the one `unscoped` call
  (`Client` merge) is limited to ids already loaded in the business.
- ✓ The deliberate escape hatch, `Tenancy.across_businesses`, is used only where a token or job
  has to find its business first: client links, invitations, the mail delivery job, visit
  reminders, notification pruning and a search-reindex rake task. Each needs a written reason;
  the lookups find one record or a list of ids, then work inside that business (pruning old
  notifications across all businesses is deliberate).
- ✓ URLs carry opaque ids; another business's records are "not found" (tested with
  `assert_not_found_across_businesses`).
- pending #194 — the operator console is "not found" to everyone else, including forged POSTs.

### Mass assignment and injection

- ✓ Strong parameters everywhere; no `permit!`. The one `to_unsafe_h` (visit email settings)
  reads only known keys.
- ✓ No SQL built from interpolated input; no `constantize`/`send` on parameters.
- ✓ The few `html_safe` uses wrap fixed markup or our own SVG icons, never user input.
- ✓ Content security policy: no inline scripts or styles without the nonce, no style
  attributes, no framing (PLT-13 part 1).
- ✓ Redirects: `redirect_back_or_to` only follows same-host referers (Rails' open-redirect
  protection is on).

### Uploads

- ✓ Photos must decode as PNG, JPEG or WebP, are size- and dimension-checked from the header,
  and are re-encoded with all metadata (EXIF, GPS, comments) removed (`LogoUpload`). PDFs must
  start with `%PDF-`; nothing else is accepted (`DocumentAttachments`).
- ✓ Direct uploads are off: blobs only come from the app's own forms.
- ✓ HTML, SVG and XML are served as downloads of plain bytes (Rails default), with `nosniff`.
- fixed — scripts and stylesheets would have been served with their own content type, which the
  policy trusts from our origin: now served as plain bytes too.
- ✓ Accepted risk: blob links are bearer links that don't expire (anyone with a photo's link
  can open it). They're only shown to the business and the client the document was sent to.

### Links and public pages

- ✓ Client links: long random tokens, revocable, expiring, per-link state (ADR 0016); pages are
  `noindex`, send `Referrer-Policy: same-origin` (ADR 0018), and are rate limited per IP.
- fixed — invitation tokens were looked up before the rate limit, so guesses weren't counted.
- fixed — client-link and invitation limits returned a blank 429; now a friendly page with
  `Retry-After` (and `public/429.html` for limits that raise).
- ✓ Request form, sign-up and contact form: hidden field, a single-use form token that must be
  a few seconds old, attempts per IP (and requests per business per hour on the request form).
  Rejections are logged as `[abuse]`, which is how to tell when a lockdown is needed. Limit: a
  bot with many IP addresses that waits out the timing gets through at the per-IP rate.
- ticketed — the contact form says "thank you" but keeps nothing; MKT-02 (#111) builds it.
- ✓ Per-IP limits rely on `request.remote_ip`: behind the Cloudflare tunnel (ADR 0023) it's the
  visitor's address from `X-Forwarded-For`, trusted only from the tunnel connector
  (`TRUSTED_PROXIES`, `lib/forwarded_headers.rb`); anyone else's `X-Forwarded-For` is dropped, and
  `X-Forwarded-Host` always is. Leave `TRUSTED_PROXIES` unset and every visitor shares the
  connector's address.

### Outbound requests (SSRF)

- ✓ The only outbound fetches are email delivery and PDF rendering. The PDF browser has
  scripts disabled, its network intercepted (only `data:` and `about:` load) and a dead proxy
  as a second wall.
- ✓ No feature fetches a URL a user typed (business website and logo URLs aren't fetched).

### Payments and webhooks

- ticketed — none exist yet. PAY-03 (#95) and BIL-04 (#103) must verify the provider's webhook
  signature, reject stale timestamps, process events idempotently, and keep signing secrets in
  credentials (PLT-09).

### Escalation

- If bots get past the public forms (watch the `[abuse]` log lines): `bin/rails
  security:lockdown HOURS=24` (or `FORMS_LOCKDOWN=true`) makes public forms wait longer and allow
  fewer tries per IP. It lives in the cache, so clearing the cache ends it. A third-party
  challenge is the next step, decided then (privacy trade-off).
- ticketed — external penetration test after launch (spec out of scope).
