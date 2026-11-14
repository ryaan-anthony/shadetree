# 0006. Minitest, fixtures and Capybara for tests

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-02, and every spec (definition of done)

## Context

The original docs specified RSpec and FactoryBot. The app has about 200 Minitest tests with
fixtures, run in parallel, and CI is built around them (PLT-02). Acceptance criteria in every
spec must be covered by automated tests.

## Options considered

1. **Switch to RSpec and FactoryBot.** A popular style, but it means rewriting existing tests,
   adding dependencies, and running two frameworks during the transition.
2. **Keep Minitest with fixtures** (the Rails default), Capybara with Selenium for system tests,
   and parallel workers.

## Decision

Keep **Minitest**. Use fixtures for shared baseline data and build specific records inline when
a test needs them. Test layers:

- **Model and unit tests** for rules, calculations and validations.
- **Controller and integration tests** for requests, authorization and tenancy denial.
- **System tests** (headless Chrome) for each spec's critical user flows. Keep them few: they're
  the slowest layer.

Coverage is reported by SimpleCov (PLT-02), with no threshold until the suite stabilizes.

## Consequences

- No migration cost, and the framework Rails documentation and generators assume.
- The cross-tenant and role-matrix test helpers (PLT-06, ACC-04) are written as Minitest
  helpers.
- **Cost:** none.
