---
id: CLI-07
title: Assign and schedule requests
domain: clients
milestone: M6
depends_on: [CLI-04, JOB-02, NTF-02]
---
# CLI-07 · Assign and schedule requests

> Requirements: [04-clients](../../plans/04-clients.md) R18, R19, R20

## Summary

A request often needs a site visit or a phone call before anyone can quote it. Whoever takes the
request assigns it to a team member, with a day (today by default) and an optional time, so the
follow-up lands on that person's day. They can hand it on to someone else, at a time that fits
that person's schedule, until a quote is created or the request is archived.

## User stories

- As the person answering the phone, I want to log a request and assign it to the office manager
  for today, so it's on their list straight away.
- As an office manager, I want to reassign a request to a field tech for 2 pm tomorrow, so the
  site visit fits around their other work.
- As an owner, I want to see who has each request and which ones are overdue, so nothing waits.

## Acceptance criteria

- [x] Anyone who can manage requests can assign one to a team member (any role, active, in this
      business) with a day and, optionally, a start time or arrival window and a duration. The
      day defaults to today, and no time means "anytime that day". Assigning is offered when a
      request is created by staff and from the request page.
      *Any role that works from My day or the request page (JOB-06 lifted the interim limit).
      A blank duration is an hour for a site visit, 15 minutes for a call.*
- [x] Each follow-up is a visit or a call, chosen when assigning (visit by default), with
      optional instructions for the assignee.
- [x] A request can be reassigned and rescheduled any number of times, or unassigned. Each
      change records who, when, from and to, and shows on the request's history.
      *The History card on the request page. Setting a request back to New also unassigns it.*
- [x] Assigning a New request moves it to In progress. Creating a quote still moves it to
      Quoted, and archiving it ends the follow-up (it leaves the assignee's list).
      *Quoting ends the follow-up too. When the assignee is deactivated, removed or deletes their
      account, it ends ("they left the team") and the request goes back to New.*
- [x] The assignee is notified when a request is assigned to them, moved or taken off them,
      using the team notifications (NTF-02), with their usual email preference.
      *"A request is given to you" and "A request you have changes".*
- [x] Scheduling shows the same non-blocking warnings as visits: outside business hours, on a
      closure, or overlapping the assignee's visits or other follow-ups.
      *On the request location's hours and clock (CAT-07); visits warn about follow-ups too.*
- [x] The inbox shows each request's assignee and day, can filter by assignee (including
      "Assigned to me" and "Not assigned"), and marks requests whose follow-up day has passed as
      overdue.
      *The filter is in the URL only (?assignee=), like the quotes list's ?filter=. Overdue goes
      by each request's location's clock.*
- [x] The client timeline records when a follow-up visit is booked. Calls aren't shown there.
      *One line per follow-up, updated when it moves.*
- [x] Only people who can manage requests can assign. Assignees, members of other businesses
      and suspended businesses are refused, with tenancy and role tests.
- [x] Works on phones; the assign form is keyboard-operable and announced correctly.
      *Checked at 390 px; a browser test assigns with the keyboard alone, and axe passes.*

## Out of scope

- Showing follow-ups on the assignee's day and calendar (JOB-06, JOB-07).
- Technicians creating quotes (QTE-07).
- Telling the client about a booked site visit (backlog).
- Automatic assignment or round-robin (decision D3 stands).

## Implementation notes

- A request has one current follow-up (`request_follow_ups`); every change is in
  `service_request_events`. Visits and follow-ups share their timing (`ArrivalTiming`) and
  warnings (`VisitWarnings`). Times in a daylight-saving gap behave as visits' do.
- Dev seeds: a site visit for Priya on Thursday and an overdue call for the owner.

## Decisions

- Until JOB-06, only members who can see requests could be assigned: My day didn't show
  follow-ups yet, so a technician's notice would lead nowhere. JOB-06 lifted it (review, 2026-11-22).
- Two kinds, site visit and call, so calls don't take travel time on the calendar (owner, 2026-11-21).
- No client confirmation for a booked site visit yet; backlog (owner, 2026-11-21).
