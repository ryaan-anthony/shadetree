---
id: BIL-01
title: Plans & entitlements
domain: billing
milestone: M5
depends_on: [ACC-02, PLT-11]
---
# BIL-01 · Plans & entitlements

> Requirements: [09-billing](../../plans/09-billing.md) R1, R2, R3

## Summary

Define what each plan includes — prices, usage limits and features — as data that operators can
change without a deploy, and give the whole app one way to ask "can this business do X?" and
"how much of Y do they have left?". Every business starts on Free.

## User stories

- As the operator, I want to change the Free plan's quote limit without shipping code.
- As a developer, I want a single, simple check for features and limits so that gating is
  consistent everywhere.
- As an owner, I want to see what plan I'm on and what it includes.

## Acceptance criteria

- [x] Plans exist as data with: name, description, public/hidden, monthly and annual price
      display values, billing-provider price references, limits (e.g. quotes sent per period,
      team members, photo storage) and feature switches (e.g. remove "Powered by", SMS).
- [x] Every business has exactly one current plan; new businesses get the default (Free) plan;
      existing businesses are migrated to Free.
- [x] A single entitlement check answers feature availability and remaining limit for the
      current business; it is usable in views, actions, jobs and emails, and is cheap to call.
- [x] "Unlimited" is representable; per-business overrides (comped limits) are supported.
- [x] Settings → Plan shows the current plan, its limits and features, and a comparison with
      other public plans.
- [x] Existing gated behavior is wired to entitlements: "Powered by Shadetree" (CAT-02) and
      team member limit (ACC-03 invitations).
- [x] Plans are seeded in every environment; operators can edit them via console/command until
      the operator console exists.
- [x] Tests cover default plan, overrides, unlimited, and each wired gate.

## Out of scope

- Counting usage (BIL-02), enforcement UX (BIL-03), payment (BIL-04). Marketing pricing page
  (MKT-01 consumes this data).

## Open questions

- **(blocking for launch, not for build)** Final plan names, prices and limits (09-billing open
  question 2). Built with the placeholder shape from 09-billing R3, editable without a deploy.

## Decisions

- Limits are per business, plus a cap of three businesses on a free plan per owner.

## Implementation notes

- `Plan` (platform-wide): key, name, description, public, default, position, monthly and annual
  prices, provider price references, `limits` and `features` (JSON by key; a missing limit is
  unlimited). `db/seeds/plans.yml` holds Free, Starter, Pro and Business; `Plan.sync!` (every
  `db:seed` and `db:prepare`) adds missing plans and never overwrites edits.
- Each business has a `plan` (the default, Free, when created; the migration moved existing
  businesses to Free) and `plan_overrides` for comped limits or features.
- `Entitlements.for(business)` (also `business.entitlements`): `feature?`, `limit`,
  `unlimited?`, `used`, `remaining`, `within?(adding:)`. Unknown keys raise, so a typo can't
  silently gate. Quotes sent count the calendar month in the business's time zone until
  BIL-02 moves paid plans to their billing cycle.
- Gates wired: "Powered by Shadetree" on client pages and emails (`remove_powered_by`); team
  size on invitations (active members plus pending invitations); free businesses per owner.
- Operators: `bin/rails plans:list`, `plans:set PLAN= LIMIT=|FEATURE=|FIELD= VALUE=`,
  `plans:comp BUSINESS= LIMIT=|FEATURE= VALUE=` (or `CLEAR=1`), `plans:sync`.
