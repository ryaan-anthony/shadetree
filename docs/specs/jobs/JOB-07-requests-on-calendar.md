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

- [x] The day and week views show assigned follow-ups for the people in view, at their time
      (or with the anytime items), styled differently from job visits and labelled as a site
      visit or call, with the client name.
      *A dashed edge, a call lighter still (white), "Site visit / Call for a request" with an
      icon. Shown to people who can see requests (see Decisions).*
- [x] Opening one shows the request summary with Open request, Move, Reassign and Unassign, for
      people who can manage requests.
      *Reassign opens the assign form; Unassign comes back to the calendar.*
- [x] Follow-ups can be moved to another time, day or person by drag on desktop and by the same
      keyboard-operable flow as visits (JOB-03), with the same warnings and an Undo.
- [x] Booking from an empty slot offers "Request follow-up" alongside "Visit", listing open
      requests that need one (unassigned or unscheduled first).
      *"Or a request follow-up" in the slot's panel, then the assign form with the slot's day,
      time and person, and back to the calendar.*
- [x] The person filter, the colour by person or status, and the phone agenda include
      follow-ups.
      *Booked hours count them; "Not assigned" never has one (a follow-up always has someone).*
- [x] Moves and reassignments notify as in CLI-07, and are refused for people who can't manage
      requests, with tests for roles and tenancy.

## Out of scope

- Client self-booking of site visits (backlog, decision D1).
- Calendar feeds (backlog).
- A "Busy" block for roles that schedule but can't see requests, so they see a person's
  follow-up time without its details (JOB-08).

## Implementation notes

- Visits and follow-ups share the grid (ScheduleView "items"), warnings, the Undo toast, the
  panel and the drag controller; moves go through CLI-07's assign. For #289's "Next visit" hint
  on an empty week, ScheduleView#next_follow_up_after gives the next follow-up (to wire in once
  #289's hint lands). Dev seeds put follow-ups on the demo week (Marcus's Monday site visit,
  Priya's Thursday one, the owner's call) and leave one open request unassigned.

## Decisions

- Calls appear too, styled lighter than site visits (owner, 2026-11-21).
- Follow-ups are shown to, and moved by, people who can see requests; a schedule-only role
  sees the visits. Superseded by JOB-08: such a role now sees others' follow-ups as "Busy".
- Booking an already-assigned request from a slot moves its follow-up there (the form says
  what it is now); done ones aren't offered, as they wait for the quote or a pass back.
