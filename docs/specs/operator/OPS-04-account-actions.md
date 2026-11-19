---
id: OPS-04
title: Account actions
domain: operator
milestone: M5
depends_on: [OPS-02, BIL-05, PLT-11]
---
# OPS-04 · Account actions

> Requirements: [10-operator](../../plans/10-operator.md) R9–R12

## Summary

Give operators the handful of actions needed to run the business: suspend abusive accounts,
help with plans, fix sign-in problems, honor deletion requests, and manage plans, presets and
feature flags — each one audited and hard to do by accident.

## User stories

- As an operator, I want to suspend a business sending spam through our domain immediately.
- As the founder, I want to comp a plan for an early beta user.
- As an operator, I want to delete a business and all its data when its owner requests it.

## Acceptance criteria

- [ ] Suspend/reactivate a business with a required reason: suspended businesses' members can't
      use the app (they see a contact-support page); client links show a neutral unavailable
      page; in-flight provider payments still settle and are recorded.
- [ ] Comp a plan (with optional end date), extend a trial, and apply a provider coupon, all
      reflected in BIL-01 entitlements and the billing provider.
- [ ] For a user: resend confirmation, send password reset, unlock account.
- [ ] Schedule a business for deletion (typed confirmation of the business name); after a
      waiting period (default 30 days, expeditable) all its data and files are permanently
      removed, provider subscription canceled; the owner is notified at schedule and completion.
- [ ] Simple forms let operators edit plans (BIL-01), industry presets (CAT-05) and feature flags
      (PLT-11), replacing console-only management.
- [ ] Every action is confirmed, recorded in the audit log, and reversible where possible
      (deletion is cancellable during the waiting period).
- [ ] Tests cover each action's effects, client-link behavior under suspension, deletion
      completeness (no orphaned records or files) and audit entries.

## Follow-ups

- Add Trial / Past due / Suspended / payment-account status and billing history to the OPS-02
  directory and business page (OPS-02 shows Active and Closed only until then).

## Out of scope

- Self-serve business deletion by owners (backlog). Refunds (provider dashboard).

## Open questions

- Should suspension pause the business's subscription billing automatically? Recommend operator
  decides per case via the provider dashboard.
