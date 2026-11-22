---
id: JOB-07
title: Request follow-ups on the calendar
domain: jobs
milestone: M6
depends_on: [CLI-07, JOB-03]
---
# JOB-07 · Request follow-ups on the calendar

> Requirements: [06-jobs](../../plans/06-jobs.md) R8, R9, R15

## Summary

Whoever plans the day needs to see request follow-ups next to job visits, so a site visit can be
slotted into a tech's afternoon instead of guessed at. Scheduled follow-ups appear on the staff
calendar, look different from job visits, and can be moved and reassigned the same ways.

## User stories

- As an office manager, I want to see that a tech is free from 2 to 3 pm before I give them a
  site visit, so the day fits together.
- As an owner, I want unscheduled and unassigned requests listed beside the calendar, so I can
  book them in.

## Acceptance criteria

- [ ] The day and week views show assigned follow-ups for the people in view, at their time
      (or with the anytime items), styled differently from job visits and labelled as a site
      visit or call, with the client name.
- [ ] Opening one shows the request summary with Open request, Move, Reassign and Unassign, for
      people who can manage requests.
- [ ] Follow-ups can be moved to another time, day or person by drag on desktop and by the same
      keyboard-operable flow as visits (JOB-03), with the same warnings and an Undo.
- [ ] Booking from an empty slot offers "Request follow-up" alongside "Visit", listing open
      requests that need one (unassigned or unscheduled first).
- [ ] The person filter, the colour by person or status, and the phone agenda include
      follow-ups.
- [ ] Moves and reassignments notify as in CLI-07, and are refused for people who can't manage
      requests, with tests for roles and tenancy.

## Out of scope

- Client self-booking of site visits (backlog, decision D1).
- Calendar feeds (backlog).

## Decisions

- Calls appear too, styled lighter than site visits (owner, 2026-11-21).
