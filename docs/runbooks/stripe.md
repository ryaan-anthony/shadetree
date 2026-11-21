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

## Connect (client payments)

Businesses take card payments from their clients through their own Stripe accounts (Connect
Standard, PAY-03 and PAY-04, [ADR 0024](../adr/0024-stripe-connect-standard-direct-charges.md)).
Keys come from the environment only, never code or chat: test-mode keys on staging and
development, live-mode keys on production only.

| Variable | What |
| --- | --- |
| `STRIPE_SECRET_KEY` | Secret (or restricted) API key; `sk_live_`/`rk_live_` means live mode, and events from the other mode are ignored |
| `STRIPE_CONNECT_WEBHOOK_SECRET` | Signing secret of the connected-accounts endpoint (`/webhooks/stripe/connect`) |
| `STRIPE_CONNECT_CLIENT_ID` | The platform's Connect client id (`ca_…`, Settings → Connect → Onboarding options → OAuth), used to disconnect accounts |

Without `STRIPE_SECRET_KEY` Settings → Payments says online payments aren't available yet;
without the webhook secret the endpoint answers 503 and Stripe retries. In development, deleting
a business when `STRIPE_CONNECT_CLIENT_ID` isn't set skips the disconnect.

### Setting up an environment (test and live mode alike)

1. Connect → Settings: the platform profile (name "Shadetree", icon, brand color, a support
   email on getshadetree.com, website https://getshadetree.com), and the United States as the
   only country.
2. Webhooks → Add endpoint → **Events on connected accounts**:
   `https://<host>/webhooks/stripe/connect` with `account.updated`,
   `account.application.deauthorized`, `checkout.session.completed`,
   `checkout.session.async_payment_succeeded`, `payment_intent.succeeded`, `charge.refunded`,
   `charge.dispute.created`, `charge.dispute.updated`, `charge.dispute.closed`. Put its signing
   secret in `STRIPE_CONNECT_WEBHOOK_SECRET`.
3. In test mode, connect a business, then disconnect it from Settings → Payments, and check the
   account shows as disconnected in Stripe (Connect → Accounts). Accounts Shadetree creates
   (`Account.create(type: "standard")`) are disconnected with OAuth deauthorize; if Stripe
   refuses that for them, disconnecting fails with Stripe's message and nothing changes in the
   app: remove the account from the platform in the Stripe dashboard instead, then mark it
   disconnected (`docker exec shadetree-<env> bin/rails runner` with
   `PaymentAccount#update!(disconnected_at:, disconnected_reason: "owner")`), and report it so
   the code can follow.
4. Locally: `stripe listen --forward-connect-to localhost:3000/webhooks/stripe/connect` prints a
   secret to use as `STRIPE_CONNECT_WEBHOOK_SECRET`.

### When something looks wrong

- Events are kept 90 days in `connect_events` (type, account, status, attempts, the fields the
  app uses; no personal details). A failed event is retried by its job, then every 10 minutes by
  `RetryConnectEventsJob`, up to 8 tries; after that it's reported once and left `failed`.
  To look: `docker exec shadetree-<env> bin/rails runner 'pp ConnectEvent.where(status: "failed").pluck(:event_id, :event_type, :attempts, :error)'`.
  To try one again after fixing the cause, set its `attempts` to 0; the sweeper picks it up.
- A business's account status is refreshed by `account.updated` (older events are skipped) and
  whenever the owner comes back from Stripe's onboarding.
- Deleting a business (OPS-04) disconnects its account first; if Stripe can't be reached the
  deletion waits for the next day's run. The business keeps its Stripe account.
