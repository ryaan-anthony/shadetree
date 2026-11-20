---
id: PAY-03
title: Connect online payments
domain: payments
milestone: M4
depends_on: [CAT-01, ACC-04]
---
# PAY-03 · Connect online payments

> Requirements: [07-payments](../../plans/07-payments.md) R8, R9

## Summary

To accept cards, a business connects its own merchant account through the payment provider's
hosted onboarding. The business is the merchant of record and receives payouts directly;
Shadetree never touches card data or holds funds.

## User stories

- As an owner, I want to start accepting card payments in a few minutes so that clients can pay
  from the invoice.
- As an owner, I want to see whether my payment account is ready, and what to fix if not.

## Acceptance criteria

- [x] Settings → Payments lets the Owner start provider-hosted onboarding, return to Shadetree
      afterward, and resume onboarding if interrupted.
- [x] The connection status is shown accurately: not connected, onboarding incomplete, pending
      verification, active, restricted (with the provider's reason and a link to fix).
- [x] Status stays in sync via the provider's notifications, processed reliably and
      idempotently, not only on redirect.
- [x] Owners can disconnect; disconnecting hides Pay buttons on existing invoices without
      breaking the pages.
- [x] Only Owners can connect/disconnect; Admins can view status.
- [x] Provider credentials and signing secrets are stored securely per PLT-09; staging uses the
      provider's test mode.
- [x] A link to the provider's dashboard is offered for payouts, refunds and disputes.
- [x] Tests cover status transitions (using provider test fixtures/mocks), permissions and
      tenancy.

## Follow-ups

- Add Trial / Past due / payment-account status and billing history to the OPS-02 directory
  and business page (OPS-02 shows Active, Suspended and Closed until then).

## Out of scope

- Taking payments (PAY-04). Platform application fees (open question, 09-billing).
- Multiple providers.

## Decisions

- Stripe Connect **Standard** accounts, US only at launch (owner accepted both recommendations).
  One payment account per business, for all its locations (CAT-07; per-location payouts aren't
  built). See [ADR 0021](../../adr/0021-stripe-connect-standard-direct-charges.md).
- Deleting a business (OPS-04) disconnects its account (Shadetree's access ends) and never
  deletes the business's Stripe account. If Stripe can't be reached, nothing is deleted and the
  daily job tries again.

## Implementation notes

- `PaymentAccount` (business-owned; one connected per business, disconnected ones kept) holds the
  Stripe account id and a copy of its status: Setup not finished (details not submitted),
  Pending verification, Active (charges and payouts on, nothing due), Restricted (Stripe's reason
  in words, with a link back into onboarding to fix it). Pay buttons need charges enabled.
- Settings → Payments (`/admin/payments`): Owners (`billing`) start onboarding (a Standard account,
  then an Account Link), come back to `return` (the status is fetched) or `resume` (a fresh
  link), and disconnect (OAuth deauthorize); Admins (`business_settings`) see the status. Blocked
  while support views as a member (OPS-03). Only this page's CSP adds `connect.stripe.com` to
  `form-action` (PLT-13).
- `POST /webhooks/stripe/connect`: signature-checked, each event stored once (`ConnectEvent`,
  only the fields acted on, pruned after 90 days), processed by `ProcessConnectEventJob`:
  `account.updated` syncs, `account.application.deauthorized` marks it disconnected. Unknown
  accounts are ignored; a failed event is retried on Stripe's redelivery; nothing is logged.
- All Stripe calls go through `PaymentGateway`; tests use `FakePaymentGateway`. Keys, the Connect
  client id and endpoint setup: [docs/runbooks/stripe.md](../../runbooks/stripe.md).
- OPS-02 shows the status (directory badge; business page with the account id and reason).
- Dev seeds: Oakline has an active account (a made-up id).
- Still to do outside the code: live keys, the Connect platform profile, and registering the
  Connect webhook endpoint per environment (runbook).
