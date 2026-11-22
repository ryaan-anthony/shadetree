---
id: JOB-02
title: Schedule visits
domain: jobs
milestone: M3
depends_on: [JOB-01, ACC-04, CAT-06]
---
# JOB-02 · Schedule visits

> Requirements: [06-jobs](../../plans/06-jobs.md) R5, R6, R7

## Summary

A job happens through one or more visits: a date, a time or arrival window, and the team
members who will be there. Scheduling must be quick, flexible about how businesses actually
work (windows, "anytime"), and helpful about conflicts without being bossy.

## User stories

- As an owner, I want to schedule a job for Tuesday between 9 and 11 with Maria so that the
  client and Maria both know when.
- As an admin, I want to move a visit when it rains without re-entering anything.
- As an owner, I want a warning if I'm double-booking someone or scheduling on a holiday.

## Acceptance criteria

- [x] Owners/Admins add visits to a job with: date; a start time, an arrival window, or
      "anytime"; estimated duration (defaulted from catalog items/industry); assigned members
      (zero or more, any role); optional visit-specific instructions.
      *Arrival is a window, a start time, or anytime; the duration starts from the job's catalog services, else the industry default, else an hour.*
- [x] Visits can be rescheduled, reassigned and cancelled (with optional reason); each change is
      recorded with who/when.
      *Shown as each visit's history on the job page; cancelled visits can be restored.*
- [x] Non-blocking warnings appear when a visit is outside business hours, on a closure
      (CAT-06), or overlaps another visit for an assigned member.
      *Shown on the form before booking or moving a visit, with "Schedule anyway". A visit runs from its start to its latest arrival plus the duration; "anytime" visits are checked against the day.*
- [x] Visits have statuses Scheduled, In progress, Completed, Cancelled; job status updates
      accordingly (JOB-01).
      *A job with a visit under way, or work done and more to come, is In progress; visits booked and none done is Scheduled; nothing booked is Unscheduled. Completing a job finishes a visit under way and cancels ones not started; cancelling a job cancels its open visits.*
- [x] Assigned members are notified of assignment and changes (in-app/email via NTF-02 when
      available; feature works without it).
      *Through NTF-02: put on a visit, moved or updated, taken off, cancelled. Several days booked at once are one notification.*
- [x] Times are entered and shown in the business time zone (PLT-08).
- [x] Scheduling a visit is possible directly from the job page and from the "unscheduled" list.
- [x] Tests cover windows, warnings, DST, reassignment, roles and tenancy.

## Out of scope

- Calendar views and drag-to-reschedule (JOB-03). Client notifications (JOB-05).
- Recurring visits, member availability, travel time (backlog).

## Open questions

- ~~Multi-day visits (a 3-day painting job): one visit spanning days or one visit per day?~~
  *Decided: staff pick a date range (Wed–Fri) or separate dates (Thu, Fri, Mon) when scheduling,
  and each date becomes its own visit.*

## Implementation notes

- #289: when exactly one active member works visits (`Business#sole_member_who_can`), "Who's
  going" starts with them ticked and says why. An owner plus an office admin who both can work
  visits pre-ticks nobody, until default assignees arrive (#284). The date stays the browser's own
  field: typed dates work and its picker is reachable (a system test checks both, in the
  browser's locale), so no custom date control was added.