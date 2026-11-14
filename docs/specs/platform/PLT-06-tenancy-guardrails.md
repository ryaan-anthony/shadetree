---
id: PLT-06
title: Tenancy guardrails
domain: platform
milestone: M0
depends_on: [PLT-01, PLT-07]
---
# PLT-06 · Tenancy guardrails

> Requirements: [01-platform](../../plans/01-platform.md) R10; vision cross-cutting "Tenancy"

## Summary

Every business's data must be invisible to every other business. Instead of relying on each
developer to remember scoping, establish a single, enforced mechanism for "current business"
and make cross-tenant leaks hard to write and easy to test.

## User stories

- As a business owner, I need confidence that no other business can ever see my clients,
  prices or documents.
- As a developer, I want tenant scoping to happen by default so that I can't forget it.
- As a reviewer, I want a standard test that proves a feature denies cross-tenant access.

## Acceptance criteria

- [ ] There is one well-defined notion of the current business for each staff request, set
      after authentication and verified against the user's active memberships.
- [ ] Business-owned records can only be loaded through the current business by default;
      bypassing that requires an explicit, greppable, reviewed escape hatch.
- [ ] Background jobs and client-link requests carry and restore the correct business context.
- [ ] A shared test helper/pattern lets any feature assert that a member of business A gets
      "not found" (not "forbidden") for business B's records, by ID guessing in URLs and forms.
- [ ] Existing controllers (business settings, switching) use the new mechanism; the current
      JSON business-switch endpoint is replaced or hardened.
- [ ] Identifiers in staff URLs do not reveal record counts across tenants (decision recorded).
- [ ] The approach is documented in the agent/contributor guide.

## Out of scope

- Roles within a business (ACC-04). Operator access across tenants (OPS-01).

## Open questions

- ~~Row-level scoping vs. database-per-tenant?~~ Resolved: row-level (ADR 0003).
- ~~Strict mode in development and test?~~ Resolved: strict everywhere. Business-owned queries
  without a current business raise in every environment (ADR 0014).
