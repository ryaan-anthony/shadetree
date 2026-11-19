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
- ✓ Operators (OPS-01): two-factor with attempt limits and lockout, idle timeout, fresh code for
  access changes.
- ticketed — two-factor for business users: backlog (spec out of scope).

### Authorization and tenancy

- ✓ Every staff action declares a permission; undeclared actions are denied (ACC-04,
  `Authorization`), and checks use permissions, never role names.
- ✓ Tenant data is scoped by default (`BusinessOwned`, ADR 0014); the one `unscoped` call
  (`Client` merge) is limited to ids already loaded in the business.
- ✓ URLs carry opaque ids; another business's records are "not found" (tested with
  `assert_not_found_across_businesses`).
- ✓ The operator console is "not found" to everyone else, including forged POSTs.

### Mass assignment and injection

- ✓ Strong parameters everywhere; no `permit!`. The one `to_unsafe_h` (visit email settings)
  reads only known keys.
- ✓ No SQL built from interpolated input; no `constantize`/`send` on parameters.
- ✓ The few `html_safe` uses wrap fixed markup or our own SVG icons, never user input.
- ✓ Content security policy: no inline scripts or styles without the nonce, no style
  attributes, no framing (PLT-13 part 1).
- ✓ Redirects: `redirect_back_or_to` only follows same-host referers (Rails' open-redirect
  protection is on); the operator console returns only to console paths.

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
- ✓ Request form: hidden field, form timing, attempts per IP per business, requests per
  business per hour.
- ticketed — the contact form stores nothing yet; MKT-02 (#111) builds it with
  `AbuseProtection` (hidden field, timing, per-IP attempts).

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

- If bots get past the public forms: `bin/rails security:lockdown HOURS=24` (or
  `FORMS_LOCKDOWN=1`) makes public forms wait longer and allow fewer tries per IP. A
  third-party challenge is the next step, decided then (privacy trade-off).
- ticketed — external penetration test after launch (spec out of scope).
