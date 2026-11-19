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
- [x] Owners/Admins can erase a client: personal data (names, contacts, addresses, notes,
      photos of the property) is removed or anonymized; documents remain with totals intact and
      a neutral "erased client" label; the action requires typed confirmation and is logged.
- [x] Erased clients no longer match duplicate detection or search.
- [x] Exports respect tenancy; tests verify a business's export contains only its data and that
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
  gem: entries are stored or deflated, names are UTF-8. A big export comes in 1 GB parts, so no
  part needs ZIP64; more than 25 GB of files is refused up front.

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
- "Export everything" (one at a time per business; queued after the request is saved) runs
  `DataExportJob`, which writes zips of 1 GB parts with every CSV, each quote's and invoice's PDF
  as clients see it (drafts in `drafts/`; a busy renderer is retried), every attached file and
  photo (quotes, invoices, jobs, visits, requests) with its own date, and the logo. The last part
  has a README: the layout, what's never in an export (catalog, team, settings, billing,
  timelines), and anything that couldn't be included. File names are made safe for any unzip
  tool ("..", leading dots, separators; extensions kept; unique ignoring case).
- The requester gets a notification and email (`data_export_ready`, theirs alone). Owners and
  Admins download each part for 7 days, streamed from storage, and every download is logged.
  The page shows building, ready (with parts) or why the last one failed. A build that stops
  moving for 30 minutes (a deploy) is marked failed, so it can't block a new one.
  `PruneDataExportsJob` (daily) removes zips once their link expires and marks stopped builds.

Part 3 (erasing a client):
- "Erase their details…" on a client (`export_data`) explains what goes and what stays and needs
  the client's name typed. `ClientErasure` removes their name, company, contacts, notes, tags,
  timeline and timeline notes; blanks their addresses ("Erased address") and access notes; on
  their quotes, invoices and jobs removes messages, instructions, internal notes and attachments,
  and every stored PDF (current and each revision's; files are deleted after the change commits);
  on requests removes contact details, description, address, photos and notes; on visits removes
  instructions, client notes, photos and notes. Signed approvals keep what was agreed (line items
  and totals) without who signed or from where, and are signed again as they now are, so they
  still verify.
- Their name (full, and first and last on their own), company, emails, phones (however
  punctuated) and address lines are replaced with "[erased]" in titles, line items, terms,
  revision snapshots, document and visit histories, payment notes and references, notifications
  and email subjects about them. Other clients' notes are scrubbed of the strong identifiers only
  (full name, company, emails, phones, address), so a shared first name isn't touched. Who
  documents were sent to (and cc) is blanked, client-link activity removed and every link revoked.
- Open requests are archived and upcoming visits cancelled, directly (nobody is notified).
- Afterwards nothing reaches the client: `sendable?` is false, `mark_sent!` and
  `record_response!` refuse, and `ClientLink.issue!` raises `ClientErased` (staff pages redirect
  with a message; a queued client email is skipped). The client can't be restored or edited.
- Numbers, line items, totals and payments stay, under "Erased client" (archived; never found by
  search or duplicate matching). Ready full exports are removed, and the erasure is in the data
  log (who, when).
- Kept on purpose: email suppressions (an address that bounced or complained stays blocked, a
  legitimate interest to state in MKT-03's privacy notice).
