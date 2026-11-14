# 0014. Tenant scoping enforced by default, opaque ids in URLs

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-06; every spec that stores business data

## Context

ADR 0003 chose row-level tenancy: every business-owned row has a `business_id`. That only works
if every query remembers to filter by it. The original code looked businesses up in several
inconsistent ways (session, "newest membership", unchecked ids in a JSON endpoint). Sequential
ids in URLs also tell any signed-in user roughly how many businesses and records the platform
has.

## Options considered

1. **Convention plus review.** Scope through `current_business.clients` and hope. One missed
   `Client.find` leaks data.
2. **The `acts_as_tenant` gem.** Default scoping and a `without_tenant` escape hatch. But it
   adds a dependency for about 60 lines of code, and its job integration targets Sidekiq.
3. **A small in-house concern** (`BusinessOwned`) over `Current.business`, failing closed, with
   one greppable escape hatch, job context capture, and a shared test helper.

## Decision

- `Current.business` is set once per staff request by `BusinessContext`, from the session,
  only if the user has an **active** membership; otherwise it falls back to their newest active
  membership. Setting it also sets `Time.zone`.
- Models whose rows belong to a business `include BusinessOwned`. Queries are scoped to
  `Current.business`. **With no current business, they raise** (`Tenancy::NoBusinessError`) in
  every environment instead of returning unscoped rows. New records take the current business
  and can't be created in another, and `business_id` is read-only.
- The only bypass is `Tenancy.across_businesses(reason: "…") { }`, which logs its reason.
  Reviewers grep for it. Expected callers: client-link lookups (`ClientLinkContext`), operator
  tools (OPS-*) and maintenance jobs.
- Associations a form can set by id use `belongs_to_business_record`, which rejects records
  from another business.
- Jobs capture `Current.business` at enqueue time and restore it around `perform`.
- A request for another business's record answers **404, not 403**: the scoped lookup simply
  doesn't find it. `assert_not_found_across_businesses` is the standard test.
- **Identifiers:** business-owned tables have an opaque `uid` (12 random base58 characters)
  used in staff URLs (`to_param`, `find_by_param!`), and businesses are switched by `uid`.
  Integer primary keys stay internal. Client links use the longer `public_token` (ADR 0013).

## Consequences

- Forgetting to scope can't leak data; it raises. The cost is an explicit business in jobs,
  scripts and the console (`Tenancy.with_business(b) { … }`).
- Every new business-owned table needs `business_id` (indexed), `uid` (unique) and
  `include BusinessOwned`, plus a cross-tenant test.
- Database row-level security stays available as a later defence in depth.
- **Cost:** none.
