---
id: QTE-06
title: Quote list, lifecycle & revisions
domain: quotes
milestone: M2
depends_on: [QTE-04, QTE-05]
---
# QTE-06 · Quote list, lifecycle & revisions

> Requirements: [05-quotes](../../plans/05-quotes.md) R15, R16, R18

## Summary

Owners need to see every quote's state at a glance, chase the ones going stale, and respond to
change requests by revising and resending — without losing what was sent before. This spec
completes the quote lifecycle around building, sending and approving.

## User stories

- As an owner, I want a list of quotes awaiting a response so that I can follow up.
- As an admin, I want to revise a quote after a change request and resend it.
- As an owner, I want to copy last month's quote for a similar job.

## Acceptance criteria

- [x] Quote statuses are Draft, Sent, Viewed, Changes requested, Approved, Declined, Expired,
      Archived; expiry is applied automatically at the expiry date in the business time zone.
      *Viewed is an indicator on Sent ("Not opened", "Viewed 3×"); Expired follows the date in
      the business's time zone; Archived is kept apart from status.*
- [x] The quote list shows number, client, title, total, status, sent/updated dates; filters by
      status (with an "awaiting response" shortcut), search by client name or number, and shows
      totals for the filtered set.
- [x] Editing a sent (not approved) quote creates a new revision; resending shows the client the
      latest; staff can view previous revisions and what changed. *"Revise" keeps what was sent
      (snapshot and PDF); the client sees "being updated" until the next send.*
- [x] Staff can duplicate any quote into a new draft (optionally for another client), archive and
      unarchive, extend expiry, and reopen an expired quote by revising.
- [x] The quote page shows an activity history: created, sent (to whom), viewed, responses,
      revisions, status changes, with who/when.
- [x] Quotes appear on the client page (CLI-01) and link back to their originating request.
      *The client page lists recent quotes (CLI-01); the builder and a sent quote's page both say
      "From request R-…", linking to it.*
- [x] Tests cover status transitions, auto-expiry, revisioning, duplication, roles and tenancy.

## Out of scope

- Automatic follow-up reminders (backlog). Conversion to job/invoice (JOB-01, PAY-01).

## Open questions

- ~~Should revising an approved quote be blocked (recommended, 05-quotes open question 2)?~~
  Yes: an approved quote can only be duplicated.
- ~~Is "Viewed" a status or just an indicator?~~ An indicator shown alongside Sent.
