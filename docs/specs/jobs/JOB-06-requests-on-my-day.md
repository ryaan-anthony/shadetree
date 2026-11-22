---
id: JOB-06
title: Request follow-ups on My day
domain: jobs
milestone: M6
depends_on: [CLI-07, JOB-04]
---
# JOB-06 · Request follow-ups on My day

> Requirements: [06-jobs](../../plans/06-jobs.md) R10, R15; [04-clients](../../plans/04-clients.md) R19

## Summary

Requests assigned to someone show up on their My day next to their visits, in time order, so a
site visit or call is part of the day like any other job. The assignee has what they need to
follow up (client, address, what was asked for, photos), records what they found, and either
creates the quote or hands it back or on.

## User stories

- As an office manager, I want today's assigned requests on My day, so I work through them
  between other tasks.
- As a field tech, I want an assessment at 2 pm to sit between my 1 pm and 3 pm visits, with the
  address and the client's photos, so I can plan my route.
- As an assignee, I want to note what I found and pass the request back, so whoever quotes it
  has the details.

## Acceptance criteria

- [ ] My day lists the person's assigned request follow-ups alongside their visits: timed ones
      in time order, "anytime" ones with the day's anytime items, overdue ones with anything
      still open from earlier, and the next 14 days after. Each is clearly labelled as a site
      visit or call for a request, not a job visit.
- [ ] Each shows the client name, the property address (opens maps), tap-to-call and
      tap-to-text, what was requested, the client's message and photos, and the assignee's
      instructions.
- [ ] The assignee can add notes and photos to the request (same limits and upload behaviour as
      visits), and mark the follow-up done. Marking it done keeps the request In progress and
      tells whoever assigned it (NTF-02).
- [ ] From a done follow-up, the assignee can create a quote if their role allows it (QTE-07 for
      technicians), or pass it back to the person who assigned it with a note.
- [ ] Requests can be assigned to members of any role (CLI-07 limits it to people who can see
      requests until follow-ups show on My day).
- [ ] People who can manage requests can also reassign or reschedule from My day.
- [ ] Assignees see only the requests assigned to them, and only while assigned. Direct links to
      other requests, the inbox, prices and other clients are refused, with tests for roles and
      tenancy.
- [ ] My day stays fast (under 1 s on 4G), phone-first and keyboard-operable, as JOB-04
      requires.

## Out of scope

- Showing follow-ups on the staff calendar (JOB-07).
- Route ordering and travel times (backlog).

## Decisions

- The assignee sees all internal notes on that request (owner, 2026-11-21).
