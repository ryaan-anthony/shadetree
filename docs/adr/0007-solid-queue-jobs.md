# 0007. Solid Queue for background and scheduled work

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-09, NTF-01, NTF-04, JOB-05, QTE-02, BIL-02, CLI-06, INS-02

## Context

Sending email, rendering PDFs, processing payment webhooks, visit reminders, automations, CSV
imports and exports all run in the background, some on a schedule. The original docs assumed
Sidekiq and Redis. The app already ships Solid Queue, and ADR 0002 puts its database on
PostgreSQL.

## Options considered

1. **Sidekiq with Redis.** Very fast and mature, but it adds Redis to host, back up and pay for.
2. **GoodJob.** PostgreSQL-backed, but a different gem from the Rails default.
3. **Solid Queue** (the Rails 8 default), backed by the database, with recurring tasks in
   `config/recurring.yml` and Mission Control for visibility.

## Decision

Use **Solid Queue** on its own PostgreSQL database (ADR 0002). Run it inside Puma
(`SOLID_QUEUE_IN_PUMA`) while we're on one server, and move it to a separate process when load
or isolation requires it. Recurring work (reminders, usage resets, cleanup) goes in
`config/recurring.yml`.

Jobs must be **idempotent**, because retries and duplicate webhooks happen. They also carry the
business context explicitly (ADR 0003).

## Consequences

- No Redis anywhere in the stack.
- Throughput is lower than Sidekiq's, but far beyond launch needs.
- PLT-10 adds alerting for failed jobs and queue backlog. An operator-only Mission Control
  dashboard can be mounted behind operator authentication (OPS-01).
- **Cost:** none beyond the shared database.
