# 07 · Invoices & payments

## Purpose

Get the business paid faster: turn completed work into an invoice in one tap, let the client pay
online by card from the invoice link, and keep an accurate picture of who owes what.

## Current state

Nothing implemented. The original plan bundled client payments with a large set of features
(saved cards, partial payment plans, payment schedules, tips, multiple providers).

## Requirements

### Invoices
- **R1** Create an invoice from a job, from an approved quote, or from scratch. Line items,
  discounts and taxes behave exactly as on quotes.
- **R2** Invoice fields: number (sequential per business, prefix configurable), issue date, due
  date (from payment terms: due on receipt, net 7/15/30, custom), message, terms, internal notes.
- **R3** Statuses: Draft → Sent → (Viewed) → Partially paid → Paid, plus Void. Overdue is derived
  from the due date.
- **R4** A sent invoice can be edited only by voiding and re-issuing, or by explicit revision,
  keeping an audit of changes. Paid invoices are locked.
- **R5** Invoice list with filters (status, overdue), search and totals outstanding.

### Delivery
- **R6** Send by email (button to client link + PDF), or copy link. Branded PDF matches web view.
- **R7** Client invoice page shows business, items, totals, amount paid, balance due, due date,
  and — if online payments are enabled — a Pay button.

### Online payments
- **R8** A business connects a payment account with the provider through a hosted onboarding
  flow. Shadetree never handles raw card data.
- **R9** Money from client payments goes to the business's own account; the business is the
  merchant of record.
- **R10** Clients can pay the balance (or, if allowed, a custom partial amount) by card; wallets
  (Apple/Google Pay) where the provider supports them. Bank transfer (ACH) is optional/backlog.
- **R11** Successful payment marks the invoice accordingly, emails a receipt to the client and
  notifies the business. Payment status is driven by the provider's confirmations, not by the
  browser redirect.
- **R12** Payments are idempotent: double-clicks, retries, or delayed confirmations never
  double-record.

### Recorded payments & balances
- **R13** Staff can record offline payments (cash, check, bank transfer, other) with date,
  amount, method and reference; and delete a mis-recorded one (audited).
- **R14** Partial payments are supported; balance and status update automatically.
- **R15** A client's outstanding balance is visible on the client page and in totals.

### Refunds
- **R16** Refunds are performed in the provider's dashboard at launch; Shadetree reflects
  refunds it is notified of on the invoice.

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | One payment provider at launch (Stripe recommended, Connect with hosted onboarding). | Hosted onboarding + hosted card fields keep us out of PCI scope; one integration to maintain. |
| D2 | No saved cards, autopay, payment plans or tips at launch. | Each is valuable but not required to close the loop. |
| D3 | Offline payments are first-class. | Cash and check are still common in the target market. |
| D4 | Refunds initiated in the provider dashboard at launch. | Rare, high-risk operation; avoid building UI until needed. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [PAY-01](../specs/payments/PAY-01-invoice-builder.md) | Invoice builder | M4 | QTE-01, JOB-01 |
| [PAY-02](../specs/payments/PAY-02-send-invoice.md) | Send invoice & client invoice page | M4 | PAY-01, QTE-02, PLT-12, NTF-01 |
| [PAY-03](../specs/payments/PAY-03-connect-payments.md) | Connect online payments | M4 | CAT-01, ACC-04 |
| [PAY-04](../specs/payments/PAY-04-online-payment.md) | Client pays online | M4 | PAY-02, PAY-03 |
| [PAY-05](../specs/payments/PAY-05-recorded-payments.md) | Recorded payments & balances | M4 | PAY-01 |

## Backlog (M6)

- Deposits required on quote approval.
- Overdue invoice reminders (automatic, configurable).
- ACH / bank debit; saved payment methods; autopay for recurring jobs.
- Tips on payment.
- Refunds from within Shadetree.
- Batch invoicing (e.g. all completed visits this month for a property manager).
- Accounting export/sync (QuickBooks, Xero).

## Open questions

1. **Provider (G2):** Stripe Connect Standard vs Express. Standard gives businesses their own
   dashboard (less support for us); Express gives a smoother onboarding. Recommend Standard.
   **(blocking for PAY-03)**
2. **Platform fee (see 09-billing):** do we take an application fee on client payments, e.g. on
   Free plan only? Affects PAY-04 copy and pricing page.
3. Do we pass card fees to clients (surcharging)? Legal varies by state; recommend no at launch.
4. Can clients pay a partial amount of their own choosing? Recommend business-level toggle,
   default off.
