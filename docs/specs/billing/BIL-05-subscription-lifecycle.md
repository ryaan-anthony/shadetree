---
id: BIL-05
title: Trials, failed payments & downgrades
domain: billing
milestone: M5
depends_on: [BIL-04, BIL-03]
---
# BIL-05 · Trials, failed payments & downgrades

> Requirements: [09-billing](../../plans/09-billing.md) R8, R11, R12

## Summary

Handle the edges of a subscription gracefully: an optional free trial of a paid plan, cards
that fail, and businesses that cancel or lapse. Owners should always know where they stand, and
nobody loses data because a card expired.

## User stories

- As a new owner, I want to try paid features without entering a card.
- As an owner whose card failed, I want a clear warning and time to fix it.
- As an owner who cancels, I want to keep my data and continue on Free.

## Acceptance criteria

- [x] New businesses can start with a trial of a configured paid plan (length configurable,
      0 disables); trial status and days remaining are visible; reminders are emailed before it
      ends; at the end without payment the business moves to Free.
- [x] When a renewal payment fails, Owners see a persistent banner with a link to update
      payment; the plan continues through a configurable grace period while the provider
      retries.
- [x] If the subscription ends (canceled or unpaid after grace), the business moves to Free at
      the end of the paid period; Owners are emailed; limits and features follow BIL-03
      downgrade rules; nothing is deleted.
- [x] Reactivating (paying again) restores the paid plan immediately.
- [x] All transitions are driven by provider events or scheduled checks, are idempotent, and are
      recorded in a per-business billing history visible to operators.
- [x] Tests cover trial expiry, grace, downgrade at period end, reactivation and duplicate
      events.

## Follow-ups

- Add Trial / Past due / payment-account status and billing history to the OPS-02 directory
  and business page. *Done here except the payment-account status (PAY-03).*

## Out of scope

- Dunning emails (provider handles retries and payment-failure emails).
- Win-back campaigns (backlog).

## Decisions

- A 14-day Pro trial without a card, and 7 days' grace after the first failed renewal (owner
  accepted the recommendations). Both are settings: `TRIAL_DAYS` (0 turns trials off),
  `TRIAL_PLAN`, `BILLING_GRACE_DAYS`.
- Every new business starts the trial; a trialing business counts toward the three free
  businesses per owner.

## Open questions

- Should one person get a trial on every business they create, or only their first?
  (Today: every new business; the free-business cap limits it to three at a time.)

## Implementation notes

- `Billing::PlanResolver` works the plan out in one order: an operator's comp (until its end
  date), a live Stripe subscription (to the end of a cancelled period; while past due, until
  the grace period from `subscriptions.past_due_since` ends), the business's trial, then Free.
  It keeps `businesses.billing_status` (free, trialing, active, past_due, comped) and
  `billing_check_at`; `BillingChecksJob` (hourly) re-resolves businesses that are due and sends
  trial reminders (3 days and 1 day before, once each, `Billing::TrialReminders`).
- A move to Free is in the billing history with its reason and emailed to each Owner
  (`BillingMailer#moved_to_free`); BIL-03's rules apply and nothing is deleted. Paying again
  (Stripe's retry, or a new Checkout) restores the plan as soon as the event or return arrives.
- Owners see the trial's days left and a failing renewal on Settings → Plan (with "Update
  payment method", the portal's card flow) and a banner on every page while past due (and in a
  trial's last three days).
- Operators (OPS-04): comp a plan with an optional end date, set a trial's end, apply a Stripe
  coupon or promotion code to the subscription; each needs a reason and a recent code, is
  audited and in the billing history. The directory filters Trial and Past due (OPS-02).
- Dev seeds: the demo business's subscription sets its billing status; a business created in
  development starts the 14-day trial.
- Tests: `test/models/billing/lifecycle_test.rb`, `test/integration/ops/billing_actions_test.rb`,
  `test/integration/admin/billing_test.rb`.
