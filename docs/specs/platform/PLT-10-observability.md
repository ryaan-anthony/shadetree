---
id: PLT-10
title: Observability
domain: platform
milestone: M1
depends_on: [PLT-09]
---
# PLT-10 · Observability

> Requirements: [01-platform](../../plans/01-platform.md) R19, R22

## Summary

Know when something breaks before a business owner emails us, and have enough context to fix
it, without leaking client personal data into third-party tools.

## User stories

- As the operator, I want to be alerted when error rates spike, jobs fail repeatedly or the site
  is down so that I can respond quickly.
- As a developer, I want errors grouped with the request, business and release context.

## Acceptance criteria

- [ ] Unhandled exceptions in web requests and background jobs are reported to an error tracker
      with release version, environment, and business identifier — but no client names, emails,
      phone numbers, addresses or document contents.
- [ ] Logs are structured, include a request ID, and filter sensitive parameters (passwords,
      tokens, client contact details, payment data).
- [ ] An external uptime check monitors the health endpoint and a client-link page; alerts go
      to the maintainer.
- [ ] Background job failures and queue backlog beyond a threshold raise an alert.
- [ ] Basic performance visibility exists (slow requests, slow queries) for the staff app and
      client pages.
- [ ] A personal-data inventory lists where client PII is stored and confirms none is sent to
      logs or monitoring tools.
- [ ] Monitoring tools fit within free or low-cost tiers at launch scale (recorded).

## Out of scope

- Product analytics (MKT-04, OPS backlog). Public status page.

## Open questions

- Self-hosted vs hosted error tracking — cost vs maintenance; record in an ADR.
