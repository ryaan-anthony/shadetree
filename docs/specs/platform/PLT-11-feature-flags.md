---
id: PLT-11
title: Feature flags
domain: platform
milestone: M1
depends_on: [PLT-06]
---
# PLT-11 · Feature flags

> Requirements: [01-platform](../../plans/01-platform.md) R13

## Summary

Many specs take several PRs. Feature flags let unfinished work merge to `main` dark and be
enabled for the maintainer's test business, beta businesses, or everyone — so developers work
in parallel without long-lived branches.

## User stories

- As a developer, I want to merge partial work behind a flag so that my branch never drifts far
  from `main`.
- As the product owner, I want to enable a feature for a few beta businesses before everyone.
- As an operator, I want to turn a misbehaving feature off without a deploy.

## Acceptance criteria

- [ ] Flags can be checked anywhere (views, controllers, jobs, emails) for the current business.
- [ ] A flag can be: off for all, on for all, on for a list of businesses, or on for a
      percentage of businesses (deterministic per business).
- [ ] Flags can be changed at runtime without a deploy by the maintainer (console/command or a
      minimal admin screen; the operator console UI arrives later in OPS-04).
- [ ] Undefined flags default to off and are reported in development.
- [ ] Tests can set flag state explicitly and reset between tests.
- [ ] The contributor guide explains when to use a flag and how to remove it once a feature is
      fully launched (flags have an owner and an expected removal milestone).

## Out of scope

- Plan-based feature gating (entitlements, BIL-01) — related but separate: flags are about
  release, entitlements are about what a plan pays for.

## Open questions

- Use an established library or a small in-house implementation? Engineering decision; prefer
  something that works with the chosen database without extra infrastructure.
