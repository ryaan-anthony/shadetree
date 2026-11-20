# 0025. Staging sends real email; the mail sandbox is optional

- **Status:** Accepted
- **Date:** 2026-11-20
- **Specs:** NTF-01, PLT-09; amends [ADR 0017](0017-transactional-email-smtp.md)

## Context

ADR 0017 kept staging from emailing real clients. The deploy forced the app's mail sandbox
(`MailSandbox`) on staging, so only `MAIL_ALLOWLIST` received mail, and copies of anything blocked
went to `MAIL_SANDBOX_TO`. In practice every test address, `+tag` addresses included, had to be
listed by hand, and that got in the way of testing. Staging is a controlled environment: only the
owner and known testers use it, and it never holds production data.

## Options considered

1. **Keep the forced sandbox:** safest against a stray real address. Every tester's address must
   be listed before staging will email it.
2. **Staging sends real email, with the sandbox as an option** (chosen): staging behaves like
   production, and anyone who wants the guard back sets `MAIL_SANDBOX=true`.

## Decision

Staging sends real email through its own SMTP credentials on the sending domain, like production
(owner decision, 2026-11-20). The deploy no longer forces the sandbox. `MAIL_SANDBOX` is an
optional, validated setting (`true`, `false` or unset; off by default), used with `MAIL_ALLOWLIST`
and `MAIL_SANDBOX_TO`. The deploy refuses `MAIL_SANDBOX=true` on production, where it would stop
clients getting their email.

## Consequences

- Testing on staging needs no allow-list. Whoever enters an address on staging decides who gets
  mail, so staging stays limited to people who know that.
- Bounces and complaints from staging count against the same sending domain and email account as
  production, so test addresses should be real.
- While the email account is in its provider's sandbox, the provider still limits staging to
  verified addresses.
- Deploy CI keeps exercising the sandbox with `MAIL_SANDBOX=true`.
- **Cost:** none.
