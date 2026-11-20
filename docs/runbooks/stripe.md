# Stripe runbook

Shadetree uses one Stripe account for two things, each in its own section below: billing
businesses for their plan, and businesses' own client payments (Connect). Keys and settings come
from the GitHub environment's secrets/variables (see docs/runbooks/operations.md), never code or
chat: test-mode keys on staging and development, live-mode keys on production only. API calls
time out after 5 s to connect and 15 s to read, with one retry (config/initializers/stripe.rb,
shared by both).

## Billing (subscriptions)

Shadetree bills businesses for their plan through Stripe Billing (BIL-04, BIL-05,
[ADR 0022](../adr/0022-subscription-billing-with-stripe.md)).

| Variable | What |
| --- | --- |
| `STRIPE_SECRET_KEY` | Secret (or restricted) API key |
| `STRIPE_PUBLISHABLE_KEY` | Publishable key (hosted pages only today; kept for later) |
| `STRIPE_WEBHOOK_SECRET` | Signing secret of the subscriptions endpoint (`/webhooks/stripe`) |
| `STRIPE_AUTOMATIC_TAX` | `false` turns off Stripe Tax on subscriptions (default on) |
| `TRIAL_DAYS` | Length of a new business's trial (BIL-05; default 14, `0` turns trials off) |
| `TRIAL_PLAN` | The plan trialled (default `pro`) |
| `BILLING_GRACE_DAYS` | Days a failed renewal keeps the plan before Free (default 7) |

Without `STRIPE_SECRET_KEY` the plan page still lists the plans, but choosing one or "Manage
billing" says billing isn't available right now.

### Setting up an environment (test and live mode alike)

1. In the Stripe dashboard: turn on Stripe Tax (BIL-04 uses automatic tax on subscriptions;
   prices are created tax-exclusive, so tax is added on top, as the pricing copy says); under
   Billing → Revenue recovery set retries and "if all retries fail" to **cancel the
   subscription**, with the retry window at least as long as `BILLING_GRACE_DAYS` (so a
   payment can still succeed during the grace period); and under Checkout settings turn on **limit customers to one subscription**,
   so two checkouts can't both start one.
2. Deploy, then on the VM run `docker exec shadetree-<env> bin/rails stripe:sync_plans`. It
   makes a product per paid plan, monthly and yearly prices with lookup keys
   `shadetree_<plan>_monthly` and `shadetree_<plan>_yearly`, and the customer portal's
   settings. Run it again after changing a plan's price, name or listing. The app finds prices
   by lookup key (cached an hour), so no price ids are copied between modes.
3. Add a webhook endpoint `https://<host>/webhooks/stripe` for these events, and put its signing
   secret in `STRIPE_WEBHOOK_SECRET`: `checkout.session.completed`,
   `customer.subscription.created`, `customer.subscription.updated`,
   `customer.subscription.deleted`, `invoice.paid`, `invoice.payment_failed`.

### Changing a price

Edit the plan (operator console), then run `docker exec shadetree-<env> bin/rails
stripe:sync_plans` on the VM. Stripe prices can't be edited, so a new price takes over the
lookup key and the old one is archived; existing subscribers keep the old price until they
change plan (move them in the dashboard if needed).

### Suspended businesses

Suspending a business (OPS-04) doesn't pause its subscription. Its Owners can still open
Settings → Plan and "Manage billing" (Stripe's portal) to update their card or cancel; nothing
else in the app opens for them. Pause or cancel billing in the Stripe dashboard if needed.

### Deleting a business

Scheduling a deletion (OPS-04) sets the business's live subscriptions to end with the paid
period; cancelling the deletion undoes only that (not a cancellation the Owner chose). When
the deletion runs, any subscription still live is cancelled at once. The Stripe customer, with
its billing email and invoices, is kept.

**Decision needed:** should Shadetree also delete the Stripe customer (who holds the billing
email) when a business is deleted?

### Billing email

When an Owner stops being an Owner (demoted, deactivated or their account deleted), the Stripe
customer's email is changed to a remaining Owner's, so receipts and failed-payment emails reach
someone who can act on them.
