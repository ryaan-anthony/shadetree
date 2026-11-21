# 0024. Client payments through Stripe Connect Standard, with direct charges on Checkout

- **Status:** Accepted
- **Date:** 2026-11-20
- **Specs:** PAY-03, PAY-04

## Context

Clients pay a business's invoices by card from the client link (07-payments R8–R12). The
business must be the merchant of record and be paid out directly; Shadetree must stay out of PCI
scope and never hold funds. The product owner approved Stripe Connect **Standard** accounts, US
only at launch, and one payment account per business (CAT-07; per-location payouts aren't built).

## Options considered

1. **Express accounts with destination charges**: smoother onboarding, but Shadetree is the
   merchant of record's platform, carries support for payouts, refunds and disputes, and builds
   dashboards for them. Rejected by the owner (07-payments open question 1).
2. **Standard accounts, direct charges, hosted pages**: the business has its own Stripe account
   and dashboard (payouts, refunds, disputes there); charges are created on its account; card
   entry happens only on Stripe's hosted onboarding and Checkout pages.

## Decision

Option 2. A business connects through Account Links (`account_onboarding`); Shadetree keeps the
account id and a copy of its status (`PaymentAccount`), kept in sync by `account.updated`
notifications and a fetch on return. Clients pay on a Checkout Session created on the connected
account (card only, which includes Apple Pay and Google Pay). Payments, refunds and disputes are
recorded only from signed Connect notifications (`/webhooks/stripe/connect`), stored once per
event id (`ConnectEvent`) and processed in a job; a payment is keyed by its PaymentIntent id, so
repeats never double-record. Disconnecting calls OAuth deauthorize: the business keeps its Stripe
account. Stripe calls for connected accounts go through `PaymentGateway`, kept apart from
BIL-04's `StripeGateway`, which calls Stripe as the platform itself (products, prices,
subscriptions): the two share the key and initializer but not methods, webhooks or event tables,
and each is swapped for a fake in tests. Notifications that fail are retried by the job and then
by a sweeper (`RetryConnectEventsJob`) up to eight tries, then reported once. A platform fee, if
one is ever set, is a per-plan setting (`application_fee_amount`), 0 for now.

## Consequences

- No card data or funds touch Shadetree; refunds and disputes are done in the business's own
  dashboard and reflected here from notifications (07-payments D4).
- Needs, per environment: the secret key, the Connect client id (for deauthorize) and a Connect
  webhook endpoint with its signing secret (docs/runbooks/stripe.md). Staging uses test mode.
- Wallets and anything Stripe adds to Checkout come without code; ACH and other delayed methods
  stay off until a spec handles "processing" payments.
- **Cost:** no fixed cost; Stripe's per-transaction fees are paid by the business.
