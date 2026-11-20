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

Without `STRIPE_SECRET_KEY` the plan page still lists the plans, but choosing one or "Manage
billing" says billing isn't available right now.

### Setting up an environment (test and live mode alike)

1. In the Stripe dashboard: turn on Stripe Tax (BIL-04 uses automatic tax on subscriptions;
   prices are created tax-exclusive, so tax is added on top, as the pricing copy says); under
   Billing → Revenue recovery set retries and "if all retries fail" to **cancel the
   subscription**; and under Checkout settings turn on **limit customers to one subscription**,
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
