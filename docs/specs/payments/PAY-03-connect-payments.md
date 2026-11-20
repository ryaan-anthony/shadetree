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

- [ ] Settings → Payments lets the Owner start provider-hosted onboarding, return to Shadetree
      afterward, and resume onboarding if interrupted.
- [ ] The connection status is shown accurately: not connected, onboarding incomplete, pending
      verification, active, restricted (with the provider's reason and a link to fix).
- [ ] Status stays in sync via the provider's notifications, processed reliably and
      idempotently, not only on redirect.
- [ ] Owners can disconnect; disconnecting hides Pay buttons on existing invoices without
      breaking the pages.
- [ ] Only Owners can connect/disconnect; Admins can view status.
- [ ] Provider credentials and signing secrets are stored securely per PLT-09; staging uses the
      provider's test mode.
- [ ] A link to the provider's dashboard is offered for payouts, refunds and disputes.
- [ ] Tests cover status transitions (using provider test fixtures/mocks), permissions and
      tenancy.

## Follow-ups

- Add Trial / Past due / payment-account status and billing history to the OPS-02 directory
  and business page (OPS-02 shows Active, Suspended and Closed until then).

## Out of scope

- Taking payments (PAY-04). Platform application fees (open question, 09-billing).
- Multiple providers.

## Open questions

- **(blocking)** Provider and account type (G2; 07-payments open question 1): Stripe Connect
  Standard (recommended) vs Express.
- Which countries can connect at launch? Recommend US only, matching G7.
