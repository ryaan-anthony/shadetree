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

- [ ] Owners/Admins can download CSVs for: clients, properties, requests, quotes (and line
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

## Open questions

- Legal retention requirements for invoices vs erasure (12-insights open question 3).
- Should Technician-uploaded photos be included in exports? Recommend yes.
