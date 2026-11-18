---
id: JOB-03
title: Staff calendar
domain: jobs
milestone: M3
depends_on: [JOB-02]
---
# JOB-03 · Staff calendar

> Requirements: [06-jobs](../../plans/06-jobs.md) R8, R9

## Summary

Replace the whiteboard. Owners and admins see who is where, when — by day or week, for everyone
or one person — spot gaps, and move work around quickly, on a desktop or a phone.

## User stories

- As an owner, I want to see this week's visits for my whole crew so that I can balance the load.
- As an admin on desktop, I want to drag a visit to another day or person.
- As an owner on my phone, I want an agenda of today and tomorrow.

## Acceptance criteria

- [x] Day and week views show visits by time (start time or window; "anytime" visits in an
      all-day row) with client name, property area, job title and assignees; colored by
      assignee or status.
- [x] Filter by member (including "unassigned"); jump to today; navigate periods.
- [x] Off-hours and closures from CAT-06 are visually shaded.
- [x] An "unscheduled" panel lists jobs needing visits; scheduling from it is quick.
- [ ] On desktop, visits can be dragged to a new time/day/member, with the same warnings as
      JOB-02 and undo; on mobile, a quick-edit sheet offers the same changes.
- [x] On mobile, the default view is an agenda list grouped by day.
- [x] Opening a visit shows its details and links to the job.
- [x] The calendar loads quickly with 200 visits in a week for 10 members.
- [x] Technicians do not see the team calendar; they use their day view (JOB-04).
- [ ] Tests cover filtering, rescheduling, warnings and tenancy (system tests for drag/quick-edit).

## Implementation notes

- Part 1 (the views, filters, shading, "Needs scheduling", the visit panel) is one PR; dragging,
  undo and the phone quick-edit sheet are part 2.
- A window visit fills the grid from the window's start to its latest finish (window end plus
  duration), the same span the JOB-02 overlap warnings use.
- Visits that overlap share their day's width side by side; a short visit is drawn at least
  22 px tall so its text can be read.
- On phones the agenda comes first and this week's past days are folded into "Earlier this week".
- Measured: a week of 200 visits for 10 people renders in about 0.6 s with 23 queries (test).

## Out of scope

- Month view, map view, route optimization, calendar feed export (backlog).

## Open questions

- Should Technicians be allowed a read-only team calendar? Recommend a business setting later.
