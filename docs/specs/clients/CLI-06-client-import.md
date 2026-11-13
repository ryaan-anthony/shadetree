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

- [ ] Owners/Admins upload a CSV (size and row limits stated); common exports from spreadsheets
      and popular tools are handled (encodings, header variations).
- [ ] Columns are auto-mapped where names are recognizable and can be re-mapped manually to
      client name, company, email, phone, address fields, notes and tags.
- [ ] A preview shows the first rows as they will be imported, plus validation errors and likely
      duplicates (existing clients matching email/phone).
- [ ] The user chooses how to handle duplicates: skip or create anyway (no automatic merge).
- [ ] Imports run in the background for large files; the user sees progress and gets an
      email/in-app summary: created, skipped, failed (downloadable error report).
- [ ] An import can be undone within a time window (removes only the clients it created that
      have no documents yet).
- [ ] A sample CSV template is downloadable.
- [ ] Tests cover mapping, duplicates, error reporting, undo and tenancy.

## Out of scope

- Importing quotes, jobs or invoices. Importing directly from other tools' APIs (backlog).

## Open questions

- Row limit on Free plan? Recommend the same for all plans (import helps activation).
