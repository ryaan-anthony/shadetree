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

- [x] My day lists the person's assigned request follow-ups alongside their visits: timed ones
      in time order, "anytime" ones with the day's anytime items, overdue ones with anything
      still open from earlier, and the next 14 days after. Each is clearly labelled as a site
      visit or call for a request, not a job visit.
      *"Site visit for a request" / "Call for a request" with their own icon. A done one stays
      (marked Done) until it's quoted or passed back. Each is placed on its location's day.*
- [x] Each shows the client name, the property address (opens maps), tap-to-call and
      tap-to-text, what was requested, the client's message and photos, and the assignee's
      instructions.
      *On the follow-up's own page (/admin/my-day/requests/…), as a visit's is.*
- [x] The assignee can add notes and photos to the request (same limits and upload behaviour as
      visits), and mark the follow-up done. Marking it done keeps the request In progress and
      tells whoever assigned it (NTF-02).
      *Notes are the request's internal notes; site photos sit beside the client's.*
- [x] From a done follow-up, the assignee can create a quote if their role allows it (QTE-07 for
      technicians), or pass it back to the person who assigned it with a note.
      *Passing back puts it on their day, today and anytime; the note (optional) is an internal note.*
- [x] Requests can be assigned to members of any role (CLI-07 limits it to people who can see
      requests until follow-ups show on My day).
      *Any role with My day (field_work) or the request page (office); a role with neither, or
      a role change to one, ends their follow-ups.*
- [x] People who can manage requests can also reassign or reschedule from My day.
      *"Move or reassign" on the follow-up's page opens the assign form.*
- [x] Assignees see only the requests assigned to them, and only while assigned. Direct links to
      other requests, the inbox, prices and other clients are refused, with tests for roles and
      tenancy.
- [x] My day stays fast (under 1 s on 4G), phone-first and keyboard-operable, as JOB-04
      requires.
      *34 queries with the seeds; about 170–420 ms warm in development. Axe passes on My day and
      the follow-up's page, and a browser test opens one and marks it done by keyboard.*

## Out of scope

- Showing follow-ups on the staff calendar (JOB-07).
- Route ordering and travel times (backlog).
- The office removing site photos (only the person following it up can, while it's theirs);
  a quote made from the request attaches the client's photos, not site photos (backlog).
- Photo links through an authorised controller, as support ticket files have (backlog): request
  and visit photos use lasting signed links, so someone moved off a request keeps working links.

## Implementation notes

- Follow-ups and visits share the photo handling (SitePhotos) and the warnings (a done
  follow-up doesn't clash). Office staff see site photos and Done on the request and the inbox.
- Dev seeds: Marcus (tech@example.com) has a site visit for a request at 9:30 on the demo
  week's Monday, between his visits there, with a client photo; one on the Friday before is
  done, with his site photo and note, and its history has a pass back.

## Decisions

- The assignee sees all internal notes on that request (owner, 2026-11-21).
- Any role with My day or the request page can be assigned; one with neither can't, as there'd
  be nowhere to see it.

## Open questions

- Should Home's "Your visits today" (#289) count follow-ups too? With My day off the office
  menu there, an office manager with only follow-ups would see "Nothing booked". Asked of the
  owner; Home is unchanged until then.
