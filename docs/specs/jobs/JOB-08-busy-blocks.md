---
id: JOB-08
title: Busy blocks for schedulers without requests
domain: jobs
milestone: M6
depends_on: [JOB-07, ACC-07]
---
# JOB-08 · Busy blocks for schedulers without requests

> Requirements: [06-jobs](../../plans/06-jobs.md) R16

## Summary

Request follow-ups are shown on the calendar only to people who can see requests (JOB-07), so a
dispatcher who schedules visits but can't see requests books a tech into an afternoon that's
already taken. Show them each follow-up as an anonymous "Busy" block: the time is visible, the
client, request and kind aren't, and they can't open or move it.

## User stories

- As a dispatcher, I want to see that Marcus is busy from 2 to 3 pm before I give him a visit,
  without seeing the office's requests.
- As an owner, I want a scheduling-only role to plan around site visits without being given the
  clients and requests behind them.

## Acceptance criteria

- [ ] People who can see the schedule but not requests (a custom role with scheduling and without
      office access, ACC-07) see everyone else's follow-ups in view as "Busy" at their time and
      length on that person's column, or in the anytime row, with the person's name. Done ones
      show as Busy too.
- [ ] A Busy block shows no client, request, kind (site visit or call), address, instructions or
      done state. None of these, nor any request or follow-up id, are in its element ids, classes
      (no follow-up or call styling classes), data attributes, URLs, JSON, or aria and title text.
      The same rules hold in the folded "Earlier this week" agenda ("2 visits, 1 busy"). Tested on
      the page source, not just what's visible.
- [ ] It looks different from both job visits and the office's follow-up blocks (plain and muted,
      in the person's colour; neutral under colour by status), and isn't a link, drag handle or
      focusable control. Screen readers hear "Busy, 2 to 3 pm, Marcus"; a window reads "Busy,
      arriving 2 to 4 pm" and anytime "Busy, anytime". Times use the calendar's clock with its
      zone, as JOB-07's do.
- [ ] Busy blocks don't take drops or slot clicks: a visit can still be dropped or booked over
      Busy time, and warns as today ("Marcus has a request follow-up then"). The warning's words
      are deliberate: it says a follow-up, never which kind or for whom.
- [ ] Booked hours per person count Busy time, so the totals match what the office sees.
- [ ] The person filter, the location filter, the day and week views and the phone agenda
      ("2:00 pm · Busy · Marcus", not a link) include Busy blocks.
- [ ] Opening, moving, reassigning or unassigning a follow-up stays refused for these people (as
      in JOB-07), and booking from an empty slot still offers only "Visit".
- [ ] Their own follow-ups show the kind and client, as on My day (JOB-06), and open there. Only
      members with My day (field work) are ever given follow-ups, so only they have their own.
- [ ] On an empty period, the "Next visit" hint counts Busy blocks, shown as "Busy" with no detail.
- [ ] Office staff see follow-ups as JOB-07 describes; nothing changes for them.
- [ ] Tests cover what each role sees, that no request detail or id leaks (page, frames, agenda),
      windows and anytime, drops over Busy time, booked hours, refusals, and tenancy.

## Out of scope

- Other kinds of busy time (time off, personal appointments; backlog with member availability).
- Giving schedule-only roles any access to requests.

## Decisions

- A member's own follow-ups show with their details, as on My day, and open there; everyone
  else's are Busy (owner, 2026-11-22).
- Busy blocks count for the "Next visit" hint on an empty period, with no detail (owner,
  2026-11-22).
- Done follow-ups still show as Busy, with no "done" (owner, 2026-11-22).
- Accepted: a block's length, and which location filter shows it, can hint at a follow-up's
  kind and location (review of #316).
