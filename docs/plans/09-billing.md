# 09 · Plans & subscription billing

## Purpose

Charge businesses fairly for the value they get, keep a generous free tier sustainable, and do
it without building a billing system. This domain is about *our* revenue — client payments to
businesses are in 07-payments.

## Current state

Nothing implemented. `account_tier` column on users. The original plan specified building
invoice generation, dunning, payment-method storage, proration and financial reporting in-house.

## Requirements

### Plans & entitlements
- **R1** Plans are defined as data (name, monthly/annual price, provider price IDs, limits,
  features) and editable by operators without a deploy. Each business is on exactly one plan.
- **R2** An entitlement check answers two questions anywhere in the app: "is feature X available
  to this business?" and "how much of limit Y remains this period?".
- **R3** Working plan shape (prices/limits are placeholders, see open questions):

| Plan | Price | Quotes sent / month | Team members | Notable features |
| --- | --- | --- | --- | --- |
| Free | $0 | 5 | 2 | Core loop, online payments, "Powered by Shadetree" |
| Starter | ~$19 | 30 | 3 | Remove branding badge |
| Pro | ~$49 | 150 | 10 | Message templates, automations, custom roles |
| Business | ~$99 | Unlimited | Unlimited | Multiple locations, priority support |

### Usage metering
- **R4** Billable usage (quotes sent, pending G3) is counted per business per billing period,
  exactly once per event, and is visible to the business ("3 of 5 quotes sent this month").
- **R5** Free plans reset on calendar month; paid plans reset on their billing cycle.

### Limit enforcement
- **R6** Approaching a limit (e.g. 80%) shows a non-blocking notice. At the limit, the gated
  action (sending a new quote) shows an upgrade prompt instead.
- **R7** Limits never interrupt anything a client is doing: approvals, payments, and links for
  already-sent documents always work, even on a lapsed or downgraded account.
- **R8** Downgrading never deletes data; features above the plan become read-only.

### Subscriptions
- **R9** Owners upgrade, downgrade, switch monthly/annual, update payment method, view and
  download our invoices, and cancel — via the provider's hosted checkout and billing portal.
- **R10** Subscription state in Shadetree follows the provider's events (created, renewed,
  payment failed, past due, canceled), processed reliably and idempotently.
- **R11** Failed payments: provider handles retries and emails; Shadetree shows a banner, keeps
  the plan through a grace period, then moves the business to Free.
- **R12** Optional free trial of a paid plan for new businesses (length configurable; may be 0).

### Operator controls
- **R13** Operators can comp a plan, extend a trial, and apply a coupon (see 10-operator).

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Use the payment provider's subscription billing, hosted checkout and billing portal. | Invoicing, proration, tax, dunning and card storage are solved problems; avoids PCI scope. |
| D2 | Price on usage (quotes sent), not seats. | Matches value; service pros share logins to dodge seat pricing anyway. |
| D3 | Generous Free plan with the full core loop. | Mission: low-cost platform with a free tier; reduces "SaaS trap" fear. |
| D4 | Limits are soft at the edges and never break client flows. | Trust is the brand; a client hitting an error page costs the business a job. |
| D5 | Plans are data, not code. | Pricing will change often pre-product-market-fit. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [BIL-01](../specs/billing/BIL-01-plans-entitlements.md) | Plans & entitlements | M5 | ACC-02, PLT-11 |
| [BIL-02](../specs/billing/BIL-02-usage-metering.md) | Usage metering | M5 | BIL-01, QTE-04 |
| [BIL-03](../specs/billing/BIL-03-limit-enforcement.md) | Limit enforcement & upgrade prompts | M5 | BIL-02 |
| [BIL-04](../specs/billing/BIL-04-subscriptions.md) | Subscriptions via hosted checkout | M5 | BIL-01 |
| [BIL-05](../specs/billing/BIL-05-subscription-lifecycle.md) | Trials, failed payments & downgrades | M5 | BIL-04, BIL-03 |

## Backlog (M6)

- Referral program ("give a month, get a month").
- Affiliate/reseller program and white-label agency plans.
- Metered SMS add-on billing.
- Platform fee on client payments (if chosen).
- Annual-plan discount experiments.

## Open questions

1. **Usage metric (G3):** quotes sent vs jobs booked vs invoices paid. Recommend quotes sent.
   **(blocking for BIL-02)**
2. Exact prices and limits, especially Free (3 vs 5 vs 10 quotes/month)? Decide before MKT-01.
3. Platform fee on client card payments (e.g. 0.5–1% on Free only) as a revenue line instead of
   or in addition to subscriptions?
4. Trial: none (free plan is the trial) vs 14-day Pro trial? Recommend 14-day Pro trial with no
   card required.
5. Sales tax/VAT on our subscriptions — use provider tax calculation? Recommend yes.
