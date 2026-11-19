---
id: INS-02
title: Data export & client erasure
domain: insights
milestone: M5
depends_on: [CLI-01, QTE-06, JOB-01, PAY-05]
---
# INS-02 · Data export & client erasure

> Requirements: [12-insights](../../plans/12-insights.md) R5–R8; vision principle 7

## Summary

"Your data is yours" is a promise we make on the pricing page. Let a business download all of
its data at any time on any plan, and honor a client's request to be forgotten without breaking
the business's financial records.

## User stories

- As an owner, I want to export my clients and invoices to a spreadsheet for my accountant.
- As an owner leaving Shadetree, I want everything — including PDFs and photos — in one download.
- As an owner, I want to erase a former client's personal data when they ask me to.

## Acceptance criteria

- [x] Owners/Admins can download CSVs for: clients, properties, requests, quotes (and line
      items), jobs and visits, invoices (and line items), payments. Columns are documented and
      stable; money and dates are formatted for spreadsheets.
- [ ] A full-account export bundles all CSVs plus document PDFs and uploaded files into one
      archive, generated in the background; the requester receives an email/in-app link that
      expires (e.g. 7 days).
- [ ] Exports are available on every plan and are logged (who, what, when).
- [ ] Owners/Admins can erase a client: personal data (names, contacts, addresses, notes,
      photos of the property) is removed or anonymized; documents remain with totals intact and
      a neutral "erased client" label; the action requires typed confirmation and is logged.
- [ ] Erased clients no longer match duplicate detection or search.
- [ ] Exports respect tenancy; tests verify a business's export contains only its data and that
      erasure leaves no personal data in exports or search.

## Out of scope

- Scheduled exports, accounting integrations, reports (backlog). Operator-initiated full
  business deletion (OPS-04).

## Decisions

- **Erasure keeps the financial records** (owner accepted the recommendation, M5 planning):
  quotes, invoices and payments stay with their numbers and totals under "Erased client"; the
  person's details are what's removed. Where a business must keep more for tax law, it should
  export before erasing.
- **Technicians' visit photos are included in the full export** (recommendation accepted).

## Implementation notes

Part 1 (CSV downloads, the log):
- Settings → Your data (`export_data`: Owners and Admins): a CSV for clients, properties,
  requests, quotes, quote line items, jobs, visits, invoices, invoice line items and payments,
  each with its columns listed. Definitions live in `DataExport::TABLES` (new columns go at the
  end; none renamed or reordered). Money is a plain decimal in the document's currency, dates
  YYYY-MM-DD, times YYYY-MM-DD HH:MM in the business's time zone, lists joined with "; ", and
  cells a spreadsheet would run as a formula are prefixed with '.
- Every download is a `DataExport` row (who, what, when, row count), listed as "Recent exports".
