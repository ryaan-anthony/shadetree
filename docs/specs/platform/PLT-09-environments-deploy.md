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
      their domains. *Pending the owner's VMs and tunnel (ops-work).*
- [x] A merge to `main` deploys to staging automatically after CI passes.
- [x] Production deploys are triggered manually (or by tag/release) and support rollback to the
      previous release. *Tag `vX.Y.Z`; rollback re-runs an earlier deploy.*
- [x] Secrets live in the deploy platform/secret store, not in the repo; rotation is documented.
- [ ] Database and uploaded files are backed up automatically (at least daily, point-in-time if
      the database choice supports it), stored off-server, retained per a documented policy.
      *Nightly, off-machine mount, 30 days plus monthly for a year; no point-in-time recovery
      (ADR 0023), so unticked until that's accepted or added.*
- [ ] A restore has been performed into a scratch environment and the runbook updated. *The
      nightly drill and Deploy CI restore automatically; the first manual restore waits for
      the VMs.*
- [x] Background job processing and scheduled tasks run in both environments.
- [x] Staging uses test-mode credentials for all third parties and cannot email real clients
      (allow-list or sandbox). *The deploy forces the mail sandbox and refuses live Stripe keys.*
- [x] A deploy/runbook document covers deploy, rollback, restore, and rotating secrets.
- [ ] Monthly infrastructure cost is recorded against the < $50 pre-revenue target. *Hosting $0;
      domain and email still to fill in.*

### Configuration the app expects

Every variable and secret, per environment, is listed in
[the runbook](../../runbooks/operations.md#github-environments). Email (NTF-01, ADR 0017):
`APP_HOST`, `MAIL_FROM`, `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`; staging
uses the provider's sandbox credentials and `MAIL_ALLOWLIST` / `MAIL_SANDBOX_TO`.

## Out of scope

- Monitoring and alerting (PLT-10). Per-PR preview environments.

## Implementation notes

- The owner's fleet-cmdb pattern (ADR 0023): `.github/workflows/deploy.yml` (a hosted gate, then
  the self-hosted runner), `ops/deploy/deploy.sh`, `ops/backup/` (systemd user timer, lock,
  restore, drill), `.github/workflows/deploy-ci.yml` (image, deploy, backup and recovery checks).
- Puma serves HTTPS with the Origin CA certificate (`lib/server_tls.rb`); forwarded headers
  only from `TRUSTED_PROXIES` (`lib/forwarded_headers.rb`); `/up/backup` (`BackupStatus`).
- Decisions: staging backs up and drills too (it exercises the pipeline); the queue database is
  backed up, cache and cable aren't; `APP_ENVIRONMENT` tells staging's errors apart.

## Open questions

- ~~Hosting target?~~ Resolved by the owner (2026-11-20): their homelab VMs, set up in ops-work,
  deployed the fleet-cmdb way (ADR 0023). Domains: `staging.getshadetree.com`, `getshadetree.com`.
- ~~Staging data?~~ Resolved: seeded demo data only. Production data never goes to staging.
- Is a nightly backup (up to a day of data lost) enough, or is point-in-time recovery wanted?
