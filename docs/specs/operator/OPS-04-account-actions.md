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

- [x] Suspend/reactivate a business with a required reason: suspended businesses' members can't
      use the app (they see a contact-support page); client links show a neutral unavailable
      page; in-flight provider payments still settle and are recorded.
- [x] Comp a plan (with optional end date), extend or end a trial, and apply a provider coupon, all
      reflected in BIL-01 entitlements; the coupon is applied in the billing provider. *(BIL-05: the business page's
      "Plan, trial and coupon" card. A comp or trial changes the plan, not what Stripe bills,
      and a comp is refused while there's a live subscription; a coupon is applied to the
      Stripe subscription.)*
- [x] For a user: resend confirmation, send password reset, unlock account.
- [x] Schedule a business for deletion (typed confirmation of the business name); after a
      waiting period (default 30 days, expeditable) all its data and files are permanently
      removed, provider subscription canceled; the owner is notified at schedule and completion.
      *(Subscriptions are cancelled before the rows go, BIL-04.)*
- [x] Simple forms let operators edit plans (BIL-01), industry presets (CAT-05) and feature flags
      (PLT-11), replacing console-only management.
- [x] Every action is confirmed, recorded in the audit log, and reversible where possible
      (deletion is cancellable during the waiting period).
- [x] Tests cover each action's effects, client-link behavior under suspension, deletion
      completeness (no orphaned records or files) and audit entries.

## Follow-ups

- Trial, Past due and billing history came with BIL-04/05, and payment-account status with
  PAY-03 (OPS-02).

## Out of scope

- Self-serve business deletion by owners (backlog). Refunds (provider dashboard).

## Decisions

- Suspension doesn't pause subscription billing; the operator decides per case in the provider
  dashboard (recommendation accepted).
- Deletion waits 30 days and can be expedited or cancelled (10-operator open question 2). The
  business works as normal until then.
- While any of their businesses is suspended, a member can't create another business (they can
  still switch to the others). On reactivation, automations that came due during the
  suspension are skipped rather than sent late (owner's decisions).
- Comps and trial extensions change the plan in Shadetree only, not the Stripe subscription, and
  a comp stays refused while a subscription is live. Coupons are the way to change what Stripe
  bills. An extended trial still delays the first charge if the Owner subscribes during it
  (BIL-05) (owner, 2026-11-22).
- Operators can end a running trial now ("End trial" on the same card, with a reason and a recent
  code): the business moves back to Free, as when the date passes, and its Owners get the usual
  "moved to Free" email; refused while a Stripe subscription is live, since its own trial ends
  in Stripe (owner, 2026-11-28).

## Implementation notes

- Suspending sets `active: false` with `suspended_at` and the reason, so everything keyed on
  `active?` stops (client links "unavailable", request form, automations, reminders); queued
  client email isn't sent; members get a contact-support page (403) and can switch business.
  PAY-04: a suspended business's client links can't start a payment, but Stripe payments
  already under way still settle and are recorded (re-check for BIL-05).
- People: resend confirmation, password reset, unlock. Plans: name, description, listing, order,
  prices, limits, features (not key, default or provider prices). Per-business overrides need a
  reason. Presets: visit length and starter services. Flags: off, on, percentage or business IDs.
- Deletion: typed name and a reason; `DeleteScheduledBusinessesJob` (daily, or at once when
  expedited) runs `BusinessDeletion`: every table with `business_id` (children first, from the
  foreign keys), attached files with their variants and stored PDFs, flag lists; the audit log
  keeps its entries (each keeps the business's name and id, so it still reads and filters).
  Rows go in one transaction; then the audit entry, the email, and files in the background
  (`PurgeDeletedFilesJob`); one failing business doesn't stop the rest; jobs queued for a deleted
  business are dropped. Operators' notes go with it (current behaviour); people keep their
  accounts, even if it was their only business. A connected Stripe account is disconnected first
  (PAY-03; never deleted); if Stripe fails, nothing is deleted that day. The owner is emailed at schedule (with plain
  values, skipped if it's no longer due then), on cancelling and on completion.
- Suspend, reactivate, deletion, plan, override and flag changes need a code from the last 5
  minutes; every action is confirmed and audited. Tests: `test/integration/ops/account_actions_test.rb`,
  `plans_test.rb`, `presets_and_flags_test.rb`, `test/models/business_deletion_test.rb`.
