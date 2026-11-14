# 0003. Tenancy by row-level scoping in the application

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-06, and every spec that stores business data

## Context

Each business must see only its own data (vision, cross-cutting requirements). The free tier
means many small tenants, so isolation must cost nothing per tenant. Developers and agents will
add dozens of tenant-owned tables; the guardrail has to work by default rather than rely on
everyone remembering a `where`.

## Options considered

1. **Database or schema per tenant.** Strongest isolation, but migrations run N times,
   connection counts grow with tenants, and cross-tenant operator queries get awkward. It costs
   too much at free-tier scale.
2. **PostgreSQL row-level security (RLS).** Isolation enforced by the database. Strong, but it
   needs a session variable on every connection (including jobs and the console), complicates
   pooling and makes failures harder to debug.
3. **Row-level scoping in the application.** Every tenant-owned table has a `business_id`. Records
   are reached through the current business. A shared test pattern proves cross-tenant denial.

## Decision

Use **application-level row scoping**: a `business_id` on every tenant-owned record, one
well-defined "current business" per request, job and client-link visit, and records loaded
through it by default. Any query that crosses tenants must use an explicit, greppable escape
hatch, which is reviewed. PLT-06 designs the mechanism and the shared test helper.

RLS stays a possible later addition as defense in depth. If we add it, it gets its own ADR.

## Consequences

- One schema, one migration path, cheap tenants.
- Safety depends on the guardrail and on the tests every data feature must include (definition
  of done). Code review watches for the escape hatch.
- Operator features (OPS-*) are the main legitimate cross-tenant readers. They use the escape
  hatch and are audited.
- **Cost:** none beyond development effort.
