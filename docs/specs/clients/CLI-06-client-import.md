---
id: CLI-06
title: Client CSV import
domain: clients
milestone: M5
depends_on: [CLI-01]
---
# CLI-06 · Client CSV import

> Requirements: [04-clients](../../plans/04-clients.md) R8

## Summary

Switching from a spreadsheet, phone contacts or another tool should take minutes. Let a business
upload a CSV of clients, map its columns, preview the result and import — with duplicates handled
safely and a clear report of anything that didn't go in.

## User stories

- As a new owner, I want to bring my existing client list over so that I don't retype it.
- As an owner, I want to know exactly which rows failed and why.

## Acceptance criteria

- [x] Owners/Admins upload a CSV (size and row limits stated); common exports from spreadsheets
      and popular tools are handled (encodings, header variations).
- [x] Columns are auto-mapped where names are recognizable and can be re-mapped manually to
      client name, company, email, phone, address fields, notes and tags.
- [x] A preview shows the first rows as they will be imported, plus validation errors and likely
      duplicates (existing clients matching email/phone).
- [x] The user chooses how to handle duplicates: skip or create anyway (no automatic merge).
- [x] Imports run in the background for large files; the user sees progress and gets an
      email/in-app summary: created, skipped, failed (downloadable error report).
- [x] An import can be undone within a time window (removes only the clients it created that
      have no documents yet).
- [x] A sample CSV template is downloadable.
- [x] Tests cover mapping, duplicates, error reporting, undo and tenancy.

## Out of scope

- Importing quotes, jobs or invoices. Importing directly from other tools' APIs (backlog).

## Decisions

- **The same limits on every plan** (owner accepted the recommendation, M5 planning): 2 MB and
  5,000 rows per file; import helps people get started.
- **`csv` is listed in the Gemfile.** It's Ruby's own CSV library, a bundled gem since Ruby 3.4
  (no new third-party dependency).

## Implementation notes

Part 1 (upload, mapping, preview, template):
- `ClientImport` (per business): the uploaded file, its headers, `mapping` (column → field),
  the duplicate choice, counts and problems, plus each column's first value and the first 10
  rows (so the mapping page never re-reads the file). `ClientImport::CsvFile` reads UTF-8 (with
  or without a BOM), UTF-16 and Windows-1252, with comma, semicolon or tab separators (counted
  outside quotes); drops blank rows; names unnamed columns; keeps 150 columns and 1,000
  characters a cell; remembers the line each row starts on (blank lines and multi-line cells
  count) for messages; and refuses empty, oversized (checked before reading), binary or
  malformed files with a reason.
- Columns are guessed from header spellings after removing prefixes ("Home", "Billing",
  "Business"…) and numbering ("E-mail 1 - Value", "Address 1 - Street", "Main Phone #s");
  columns about another column ("… - Label", "E-mail Type", "E-mail Display Name", "Phonetic…",
  fax, pager, assistant) and empty columns are left out. Tested against Google Contacts, Outlook,
  Jobber and Housecall Pro headers. Each field once, except email and phone, which take every
  matching column; several phones in one cell are split. A row's name is the Name column, else
  first + last name, else the company, else the email.
- The mapping page lists columns that have something in them, with an example and a "Goes to"
  choice; the duplicate choice (skip, or add anyway — never merged); and a preview of the first
  10 rows (stacked on phones): "New", "Matches <existing client>" (same email or phone), or
  "Won't import" with the reason in words.
- The template (`/admin/clients/imports/template`) maps itself.

Part 2 (running, summary, report, undo):
- "Import N rows" (confirmed) queues `ClientImportJob`, which makes a client per row inside the
  business: rows that can't be saved fail with the reason; with "Skip them", rows matching an
  existing client by email or phone (including one added earlier in the same file) are
  skipped. Each row and the progress it makes are saved together, so a job stopped partway (a
  deploy) carries on from the next row when it runs again, never adding a client twice. The page
  shows a progress bar in a frame that reloads itself (`poll` controller; the rest of the page
  and the live region stay put), then shows the summary once.
- When it finishes (or breaks partway), the person who started it gets a notification and email
  (`client_import_finished`, theirs alone) with the counts; the uploaded file is deleted; the
  summary page shows added / skipped / couldn't add, the first rows not added, and a report CSV
  (line, why, then the row as uploaded; up to 1,000 rows; cells a spreadsheet would run as a
  formula are prefixed with ', except phone numbers, and that ' is dropped again if the report
  is fixed and uploaded). The preview rows and examples are cleared too.
- Undo for 7 days, also after an import that stopped partway (`ClientImportUndoJob`), removes
  the clients it added (with their notes), except ones that already have quotes, requests, jobs
  or invoices, checked under a lock per client; it always finishes, and says how many were kept.
- `PruneClientImportsJob` (daily) deletes uploads left at the mapping step for 2 days and the
  rows kept for the report once undo is over, and starts again any import or undo whose job was
  lost (no progress for an hour).
