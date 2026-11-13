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

- [ ] Plans exist as data with: name, description, public/hidden, monthly and annual price
      display values, billing-provider price references, limits (e.g. quotes sent per period,
      team members, photo storage) and feature switches (e.g. remove "Powered by", SMS).
- [ ] Every business has exactly one current plan; new businesses get the default (Free) plan;
      existing businesses are migrated to Free.
- [ ] A single entitlement check answers feature availability and remaining limit for the
      current business; it is usable in views, actions, jobs and emails, and is cheap to call.
- [ ] "Unlimited" is representable; per-business overrides (comped limits) are supported.
- [ ] Settings → Plan shows the current plan, its limits and features, and a comparison with
      other public plans.
- [ ] Existing gated behavior is wired to entitlements: "Powered by Shadetree" (CAT-02) and
      team member limit (ACC-03 invitations).
- [ ] Plans are seeded in every environment; operators can edit them via console/command until
      the operator console exists.
- [ ] Tests cover default plan, overrides, unlimited, and each wired gate.

## Out of scope

- Counting usage (BIL-02), enforcement UX (BIL-03), payment (BIL-04). Marketing pricing page
  (MKT-01 consumes this data).

## Open questions

- **(blocking for launch, not for build)** Final plan names, prices and limits (09-billing open
  question 2).
- Should limits be per business or per owner (one person with three free businesses)?
  Recommend per business plus a cap on free businesses per user.
