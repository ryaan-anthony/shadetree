---
id: CLI-05
title: Client timeline
domain: clients
milestone: M4
depends_on: [CLI-01, QTE-06, JOB-01, PAY-01]
---
# CLI-05 · Client timeline

> Requirements: [04-clients](../../plans/04-clients.md) R6, R17

## Summary

When a client calls, whoever answers should see everything about them in one place: their
requests, quotes, visits, invoices, payments and notes, in order. Complete the client page with
related documents, balance and a chronological timeline.

## User stories

- As an admin on the phone, I want the full history with this client so that I can answer
  "where are we?" without asking around.
- As an owner, I want to see how much a client owes and has paid over time.

## Acceptance criteria

- [x] The client page lists the client's requests, quotes, jobs (with next visit) and invoices
      with status and amounts, each linking to the record.
- [x] Outstanding balance and lifetime paid are shown.
- [x] A timeline shows key events newest first: request received, quote sent/viewed/approved/
      declined, visit scheduled/completed, invoice sent/paid, payments recorded, notes added —
      with who/when.
- [x] Staff can add a free-text note to the timeline; notes are editable by their author.
- [x] The timeline is paginated and fast for long-standing clients.
- [x] Events are recorded by the owning features at the time they happen (a shared way to record
      an event exists for later specs to reuse).
- [x] Role and tenancy tests exist.

## Out of scope

- Business-wide activity/audit log (backlog). Client hub for clients themselves (backlog).

## Decisions

- Email delivery on the timeline: bounces only.

## Implementation notes

- Part 1: `ClientEvent.record!(client, kind, subject:, by:, **data)` is the shared recorder,
  called in the same transaction as what it records: request received (any source), quote
  sent, first opened, approved, declined or changes requested; visit booked and done; invoice
  sent, first opened and paid in full; payment recorded; an email to the client refused by the
  mail server. The client page shows them newest first, 25 at a time ("Show older" appends the
  next page with a turbo stream), with one query for the page plus preloads, on an index of
  (business, client, time, id).
- Events start when this ships: history from before isn't backfilled (pre-launch data only).
- Part 2: notes (`ClientNote`, added by the office team from the timeline, edited only by
  their author and marked "edited"); each job in the Work list shows its next visit; the
  Balance card adds what the client has paid in all, recorded or online. (The record lists
  show the five most recent of each kind, as CLI-01 built them.)
