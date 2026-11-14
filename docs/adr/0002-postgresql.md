# 0002. PostgreSQL is the primary database

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-01, PLT-06, PLT-07, PLT-09; global question G1

## Context

The app runs on SQLite for everything, including Solid Queue, Solid Cache and Solid Cable.
Shadetree is a multi-tenant SaaS: every business writes quotes, visits and payments
concurrently, background jobs write alongside web requests, and payment webhooks must never be
lost. Launch hosting must stay under about $50/month for staging and production combined.

## Options considered

1. **Stay on SQLite** with streaming replication (Litestream-style) to object storage.
   Cheapest (no database server), simple, fast for reads. But there is only one writer at a
   time, so scaling is vertical only, on one machine. Restore has to be proven by us, and
   ad-hoc reporting and operational tooling are weaker.
2. **PostgreSQL, self-hosted** on the app VPS. Cheap, but we own backups, upgrades and failover.
3. **Managed PostgreSQL.** Concurrent writers, point-in-time recovery, mature tooling
   (`pg_dump`, extensions, `EXPLAIN`), room for row-level security later (ADR 0003). Costs about
   $15/month for a small instance.

## Decision

Use **managed PostgreSQL** in staging and production, and local PostgreSQL in development, test
and CI. The Solid Queue, Cache and Cable databases live on the same server as separate
databases, following the Rails multi-database layout already in `config/database.yml`.

The switch is executed in **PLT-07 (schema reset)**. Since no data needs preserving, PLT-07
replaces the SQLite configuration with a clean PostgreSQL baseline instead of migrating data.

## Consequences

- Contributors need PostgreSQL locally. The README and `bin/setup` will say how (PLT-07).
- CI gains a PostgreSQL service container (PLT-07 updates the workflow).
- Backups use the provider's daily snapshots plus point-in-time recovery. PLT-09 still proves a
  restore.
- Free-text search (CLI-02) can use PostgreSQL's built-in trigram or full-text search, with no
  extra service.
- **Cost:** about $15/month for production; staging can share the instance's plan tier or use
  the provider's smallest plan, about $7–15/month. Free-tier businesses add rows, not servers.
