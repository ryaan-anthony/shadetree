---
id: PLT-09
title: Environments, deploys & backups
domain: platform
milestone: M1
depends_on: [PLT-01, PLT-02]
---
# PLT-09 · Environments, deploys & backups

> Requirements: [01-platform](../../plans/01-platform.md) R17, R18, R20

## Summary

The deploy configuration has placeholder hosts and there is no running environment. Stand up a
staging environment that deploys automatically from `main` and a production environment that is
promoted deliberately, with backups we have actually restored.

## User stories

- As the maintainer, I want every merged PR live on staging within minutes so that I can test
  real flows (emails, links, payments in test mode).
- As the operator, I want to promote a known-good build to production with one action and roll
  back just as easily.
- As a business owner, I want my data to survive a server failure.

## Acceptance criteria

- [ ] Staging and production environments exist on the hosting chosen in PLT-01, with TLS on
      their domains.
- [ ] A merge to `main` deploys to staging automatically after CI passes.
- [ ] Production deploys are triggered manually (or by tag/release) and support rollback to the
      previous release.
- [ ] Secrets live in the deploy platform/secret store, not in the repo; rotation is documented.
- [ ] Database and uploaded files are backed up automatically (at least daily, point-in-time if
      the database choice supports it), stored off-server, retained per a documented policy.
- [ ] A restore has been performed into a scratch environment and the runbook updated.
- [ ] Background job processing and scheduled tasks run in both environments.
- [ ] Staging uses test-mode credentials for all third parties and cannot email real clients
      (allow-list or sandbox).
- [ ] A deploy/runbook document covers deploy, rollback, restore, and rotating secrets.
- [ ] Monthly infrastructure cost is recorded against the < $50 pre-revenue target.

## Out of scope

- Monitoring and alerting (PLT-10). Per-PR preview environments.

## Open questions

- Hosting target (VPS with the existing deploy tool vs PaaS) — decided in PLT-01.
- Staging data: seeded demo data only, or anonymized copy of production later?
