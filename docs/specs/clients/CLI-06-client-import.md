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
- [ ] The user chooses how to handle duplicates: skip or create anyway (no automatic merge).
- [ ] Imports run in the background for large files; the user sees progress and gets an
      email/in-app summary: created, skipped, failed (downloadable error report).
- [ ] An import can be undone within a time window (removes only the clients it created that
      have no documents yet).
- [x] A sample CSV template is downloadable.
- [ ] Tests cover mapping, duplicates, error reporting, undo and tenancy.

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
  the duplicate choice, counts and problems. `ClientImport::CsvFile` reads UTF-8 (with or without
  a BOM), UTF-16 and Windows-1252, with comma, semicolon or tab separators; drops blank rows;
  names unnamed columns; and refuses empty, oversized, binary or malformed files with a reason.
- Columns are guessed from header spellings (`SYNONYMS`; any "…email…" or "…phone/mobile/cell…"
  header too). Each field once, except email and phone, which take every matching column. A
  row's name is the Name column, else first + last name, else the company, else the email.
- The mapping page shows each column with an example value and a "Goes to" choice, the
  duplicate choice (skip, or add anyway — never merged), and a preview of the first 10 rows:
  "New", "Matches <existing client>" (same email or phone), or "Won't import" with the reason
  in words.
- The template (`/admin/clients/imports/template`) maps itself.
