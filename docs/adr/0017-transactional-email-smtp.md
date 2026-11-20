# 0017. Transactional email over SMTP

- **Status:** Accepted
- **Date:** 2026-11-16
- **Specs:** NTF-01, ACC-01, ACC-03, QTE-04, PAY-02, JOB-05
- **Supersedes:** [0011](0011-transactional-email-postmark.md)

## Context

NTF-01 needs authenticated sending from the platform domain, with the business's address as
reply-to, a staging environment that can't email real clients, and low cost at launch volume.
The product owner has picked an email provider and will use it through **SMTP**, Rails' built-in
delivery method. There's no provider integration in the codebase: no SDK, no webhooks, no
provider name. The provider appears only in production configuration.

## Options considered

1. **SMTP with Action Mailer's built-in `:smtp` delivery** (chosen): no dependencies, and the
   provider can be swapped by changing settings. The app only learns what the SMTP conversation
   tells it: accepted, refused (5xx), or try later (4xx).
2. **A provider's HTTP API and event webhooks:** these would report bounces and complaints after
   delivery. That's a custom integration the product owner doesn't want.

## Decision

- **Production** sends through the provider's SMTP relay. The settings are `SMTP_ADDRESS`,
  `SMTP_PORT`, `SMTP_USERNAME` and `SMTP_PASSWORD`. Encryption is required, never just
  attempted: STARTTLS is always used on 587, implicit TLS on 465.
- **Sender:** the root domain `getshadetree.com` (vision G8), as
  `"<Business> via Shadetree" <no-reply@getshadetree.com>`, with the business's own address as
  reply-to. Message-IDs are generated on the sending domain.
- **How the SMTP reply is handled** (`ClientMailDeliveryJob`):
  - The address is suppressed only when the server refused the recipient's mailbox (status
    5.1.1, 5.1.2, 5.1.3, 5.1.6, 5.1.10 or 5.2.1). The email is marked bounced and the address
    flagged on the client page until staff send to it again.
  - Any other permanent reply (sender, policy, content), and rejected credentials, fail the email
    without blaming the address.
  - 4xx replies, timeouts and connection errors are retried with backoff for about four hours.
    Anything else is a bug: it's marked failed and re-raised for error reporting.
  - Only the reply code is kept. The server's text isn't stored or logged, because it can name
    the address.
- **Platform email** (sign-up confirmation, password reset, invitations) is also sent in the
  background, so a slow server never holds up a request.
- **Bounces and complaints after acceptance** stay in the provider's dashboard.
- **Staging** has its own SMTP credentials on the same sending domain and sends real email. It's
  a controlled environment that only emails known people (owner decision, 2026-11-20). The mail
  sandbox (`MAIL_SANDBOX=true`, `MAIL_ALLOWLIST`, `MAIL_SANDBOX_TO`) is optional.
- **Development** opens every email in the browser (letter_opener_web at `/letter_opener`).
  Tests never send.

## Consequences

- **No automatic bounce flags** for addresses the relay accepts and the recipient's server later
  bounces. Staff see those in the provider's dashboard. Adding event webhooks later would be a
  new ADR.
- **DNS for getshadetree.com** comes from the provider's domain settings: SPF (an `include:` for
  the provider, merged with any existing record), the provider's DKIM TXT record, and DMARC
  (`_dmarc` TXT `v=DMARC1; p=none; rua=mailto:dmarc@getshadetree.com`, tightened once reports are
  clean).
- **Sending from the root domain** ties the site's domain reputation to transactional mail.
  Moving to a mail subdomain later is a DNS and `MAIL_FROM` change.
- **Settings** (PLT-09): the four `SMTP_*` settings, `MAIL_FROM` and `APP_HOST`.
