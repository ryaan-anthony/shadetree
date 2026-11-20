---
id: BIL-04
title: Subscriptions via hosted checkout
domain: billing
milestone: M5
depends_on: [BIL-01]
---
# BIL-04 · Subscriptions via hosted checkout

> Requirements: [09-billing](../../plans/09-billing.md) R9, R10

## Summary

Let owners pay us. Upgrading, switching plans or billing interval, updating a card, downloading
receipts and canceling all happen through the billing provider's hosted checkout and customer
portal; Shadetree mirrors the resulting subscription state reliably.

## User stories

- As an owner, I want to upgrade with a card in under a minute.
- As an owner, I want to download my invoices for my accountant and cancel without calling.
- As the operator, I want plan state in the app to always match what the provider is billing.

## Acceptance criteria

- [x] From Settings → Plan (and upgrade prompts), the Owner chooses a plan and interval and
      completes payment in the provider's hosted checkout, then returns to Shadetree with the
      new plan active.
- [x] A "Manage billing" action opens the provider's customer portal for card updates, invoices,
      plan switches and cancellation (configured to allow only valid plan changes).
- [x] Subscription lifecycle events from the provider (created, updated, renewed, canceled,
      payment succeeded/failed) are verified, processed idempotently and in a safe order, and
      update the business's plan and period.
- [x] Proration, taxes on our subscriptions and receipts are handled by the provider.
- [x] Only Owners can access billing; Admins see the plan but not billing actions.
- [x] Each business maps to one provider customer; changing the Owner keeps billing intact.
- [x] Staging uses provider test mode; tests cover event processing (including duplicates and
      out-of-order events) with fixtures/mocks.

## Follow-ups

- Add Trial / Past due / payment-account status and billing history to the OPS-02 directory
  and business page (OPS-02 shows Active, Suspended and Closed until then). *The business page
  now shows the subscription and billing history; Trial and Past due in the directory come with
  BIL-05; the payment account with PAY-03.*

## Out of scope

- Trials, failed-payment grace and downgrade behavior (BIL-05). Coupons and comps via operator
  console (OPS-04). Referral credits (backlog).

## Decisions

- Stripe, the same provider as client payments; annual plans at about two months free; Stripe
  Tax on our subscriptions (owner accepted the recommendations). See
  [ADR 0021](../../adr/0021-subscription-billing-with-stripe.md).
- The platform fee on client payments isn't decided (09-billing open question 3; PAY-04).

## Implementation notes

- `bin/rails stripe:sync_plans` (`Billing::PlanSync`) makes a product per paid plan, monthly and
  yearly prices with lookup keys `shadetree_<plan>_<interval>`, and the portal's settings
  (switch between public paid plans, prorated; cancel at period end). The app finds prices by
  lookup key, cached an hour. Setup per mode: [docs/runbooks/stripe.md](../../runbooks/stripe.md).
- Settings → Plan: Owners (`billing` permission) choose a plan and interval; with no live
  subscription that's Checkout, otherwise the portal's confirm page (Free: its cancel flow).
  "Manage billing" opens the portal. Back from Checkout the subscription is applied at once.
  Admins see the plan only; support viewing as a member can't open billing. The plan page's CSP
  lets its forms continue to checkout.stripe.com and billing.stripe.com.
- A business is one Stripe customer (`stripe_customer_id`), made with its name and uid only;
  Checkout collects the billing email. A new Owner keeps it.
- `/webhooks/stripe` is a Rack endpoint (no params logged): signature checked, the event id
  stored once, `StripeEventJob` fetches the subscription's current state and applies it under
  the business's lock (`Billing::SubscriptionSync`), so duplicates and order don't matter.
  `ProcessStripeEventsJob` (every 15 minutes) re-runs unfinished events. `Billing::PlanResolver`
  sets the plan and `billing_cycle_anchor`; `BillingEvent` is the billing history (operators'
  business page). A second live subscription raises an operator alert.
- Deleting a business (OPS-04) cancels its subscriptions first; closing an empty business when
  its last Owner deletes their account (ACC-06) cancels them in the background.
- Tests use `FakeStripeGateway` (`StripeGateway.current`); nothing calls Stripe.
- Dev seeds: the demo business's Starter as a mirrored subscription with history (made-up ids).
