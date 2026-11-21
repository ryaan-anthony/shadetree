# 0022. Subscription billing with Stripe's hosted pages, mirrored from its events

- **Status:** Accepted
- **Date:** 2026-11-20
- **Specs:** BIL-04, BIL-05, OPS-04

## Context

Businesses pay Shadetree for their plan (09-billing R9–R12). The owner chose Stripe, the same
provider as client payments (G2), with annual plans at about two months free, Stripe Tax on our
subscriptions, a 14-day Pro trial without a card and a 7-day grace period after a failed renewal.
Shadetree must never handle card numbers (D1), plans stay data operators edit (D5), and the plan
a business is on must always match what Stripe bills, whatever order its events arrive in.

## Options considered

1. **Stripe Billing with hosted Checkout and the customer portal**, the app mirroring state
   from webhooks. Pros: Stripe does invoices, proration, tax, retries, receipts and card storage;
   no PCI scope. Cons: plan state arrives asynchronously, so the app has to cope with duplicate,
   late and out-of-order events.
2. **Embedded payment forms with our own plan-change screens.** More control over the look, but
   more code, more PCI surface and our own proration rules. Rejected.

## Decision

- Stripe Billing with hosted Checkout (new subscriptions) and the customer portal (card, invoices,
  plan and interval switches, cancellation at period end). Each business is one Stripe customer,
  created without personal details; Checkout collects the billing email.
- Products and prices are made from the Plan table by `bin/rails stripe:sync_plans`, the same way
  in test and live mode. Prices are found by lookup key (`shadetree_<plan>_<interval>`) and
  cached; no price ids are stored or hard-coded.
- One webhook endpoint for platform events. It checks Stripe's signature, stores the event id
  (a unique index makes duplicates no-ops) and queues a job; the raw payload is neither logged
  nor kept. The job **fetches the subscription from Stripe** and applies its current state, so
  processing is idempotent and the order of events doesn't matter. Returning from Checkout does
  the same at once, so the new plan is active before the webhook arrives.
- `Subscription` (one row per business) mirrors Stripe's subscription; the business's plan is
  worked out from it in one place (`Billing::PlanResolver`), and each change is written to a
  per-business billing history.
- Every Stripe call goes through `StripeGateway`; tests use an in-memory fake and never call
  Stripe.

## Consequences

- Plan changes made in the portal or the Stripe dashboard flow back through the same path.
- Stripe's settings that matter (Stripe Tax, retry rules, the webhook endpoint) are set per mode
  in the dashboard; docs/runbooks/stripe.md lists them.
- A price change needs `bin/rails stripe:sync_plans`; existing subscribers keep their old price
  until they change plan.
- **Cost:** no monthly fee; Stripe Billing's percentage on subscription revenue, Stripe Tax per
  transaction, and card fees. Free businesses cost nothing here.
