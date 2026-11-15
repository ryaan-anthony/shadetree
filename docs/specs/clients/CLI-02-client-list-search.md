---
id: CLI-02
title: Client list & search
domain: clients
milestone: M1
depends_on: [CLI-01]
---
# CLI-02 · Client list & search

> Requirements: [04-clients](../../plans/04-clients.md) R7

## Summary

Find any client in a couple of keystrokes — by name, email, phone or address — whether there are
twenty clients or five thousand, and from a phone in a truck as easily as a desktop.

## User stories

- As an admin answering the phone, I want to type part of a phone number or street and find the
  client instantly.
- As an owner, I want to filter by tag (e.g. "commercial") to see a segment of my clients.

## Acceptance criteria

- [x] A client list shows name, primary contact, primary property, tags, and (once available)
      outstanding balance and last activity.
- [x] Search matches partial name, company, email, phone (ignoring formatting) and address,
      returning results as the user types without full page reloads.
- [x] Filters: tag, archived vs active. Sort: name, recently added, recent activity.
- [x] The list paginates and stays responsive at 10,000 clients per business (seed a large
      business in tests or a benchmark to prove it).
- [x] The same search powers client pickers in quotes, jobs and invoices.
- [x] Mobile layout is a readable list with tap-to-open; desktop uses a table.
- [x] Empty states guide the user to add or import clients.
- [x] Technicians have no access; tenancy is covered by tests.

## Out of scope

- Saved views, bulk actions (bulk tag/archive) — backlog unless trivial.

## Open questions

- ~~Is fuzzy matching (typos) required, or is substring matching enough?~~ Resolved: substring
  matching at launch, on a trigram index (pg_trgm), which can also back similarity (typo)
  search later without new infrastructure.
