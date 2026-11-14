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

- [ ] From Settings → Plan (and upgrade prompts), the Owner chooses a plan and interval and
      completes payment in the provider's hosted checkout, then returns to Shadetree with the
      new plan active.
- [ ] A "Manage billing" action opens the provider's customer portal for card updates, invoices,
      plan switches and cancellation (configured to allow only valid plan changes).
- [ ] Subscription lifecycle events from the provider (created, updated, renewed, canceled,
      payment succeeded/failed) are verified, processed idempotently and in a safe order, and
      update the business's plan and period.
- [ ] Proration, taxes on our subscriptions and receipts are handled by the provider.
- [ ] Only Owners can access billing; Admins see the plan but not billing actions.
- [ ] Each business maps to one provider customer; changing the Owner keeps billing intact.
- [ ] Staging uses provider test mode; tests cover event processing (including duplicates and
      out-of-order events) with fixtures/mocks.

## Out of scope

- Trials, failed-payment grace and downgrade behavior (BIL-05). Coupons and comps via operator
  console (OPS-04). Referral credits (backlog).

## Open questions

- **(blocking)** Billing provider (G2) — recommend the same provider as client payments.
- Annual plans at launch? Recommend yes with ~2 months free.
