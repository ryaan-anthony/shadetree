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

- [ ] The client page lists the client's requests, quotes, jobs (with next visit) and invoices
      with status and amounts, each linking to the record.
- [ ] Outstanding balance and lifetime paid are shown.
- [ ] A timeline shows key events newest first: request received, quote sent/viewed/approved/
      declined, visit scheduled/completed, invoice sent/paid, payments recorded, notes added —
      with who/when.
- [ ] Staff can add a free-text note to the timeline; notes are editable by their author.
- [ ] The timeline is paginated and fast for long-standing clients.
- [ ] Events are recorded by the owning features at the time they happen (a shared way to record
      an event exists for later specs to reuse).
- [ ] Role and tenancy tests exist.

## Out of scope

- Business-wide activity/audit log (backlog). Client hub for clients themselves (backlog).

## Open questions

- Should email delivery events (bounced, opened) appear in the timeline? Recommend bounces only.
