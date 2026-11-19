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
- [x] A full-account export bundles all CSVs plus document PDFs and uploaded files into one
      archive, generated in the background; the requester receives an email/in-app link that
      expires (e.g. 7 days).
- [x] Exports are available on every plan and are logged (who, what, when).
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
  export before erasing. The legal text (MKT-03) still has to confirm this.
- **Technicians' visit photos are included in the full export** (recommendation accepted).
- **The zip is written by a small in-app writer** (`ZipWriter`, on Ruby's zlib) rather than a new
  gem: entries are stored or deflated, names are UTF-8, and the archive is capped at 2 GB (well
  under the 4 GB a ZIP without ZIP64 allows).

## Implementation notes

Part 1 (CSV downloads, the log):
- Settings → Your data (`export_data`: Owners and Admins): a CSV for clients, properties,
  requests, quotes, quote / job / invoice line items, jobs, visits, invoices, payments, and the
  client, request and visit notes, each with its columns listed. Documents carry their property,
  per-rate taxes ("State 6.25%: 15.00; County 1%: 2.40"), whether prices include tax, and
  internal notes; lines carry their discount and total. Definitions live in `DataExport::TABLES`
  (new columns go at the end; none renamed or reordered); rows come out in a fixed order (visits
  and payments by date, lines by position).
- Money is a plain decimal in the document's currency (its own decimal places), dates
  YYYY-MM-DD, times YYYY-MM-DD HH:MM in the business's time zone, lists joined with "; ". Text a
  spreadsheet would run as a formula is prefixed with ' (our numbers and phone numbers are left
  alone). Files start with a byte-order mark and are sent as UTF-8 with `no-store`.
- Every download is a `DataExport` row (who, what, when, row count), listed as "Recent exports".

Part 2 (everything in one zip):
- "Export everything" (one at a time per business) queues `DataExportJob`, which writes a zip
  with every CSV, each quote's and invoice's PDF (as clients see it), every attached file and
  photo (quotes, invoices, jobs, visits, requests) and the logo, plus a README explaining the
  layout and listing anything that couldn't be included.
- The requester gets a notification and email (`data_export_ready`, theirs alone); the zip is
  downloadable by Owners and Admins for 7 days, streamed from storage; `PruneDataExportsJob`
  (daily) removes it afterwards. The export stays in the log.
