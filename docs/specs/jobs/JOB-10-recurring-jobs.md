---
id: JOB-10
title: Recurring jobs
domain: jobs
milestone: M6
depends_on: [JOB-09, PAY-06, JOB-02]
---
# JOB-10 · Recurring jobs

> Requirements: [06-jobs](../../plans/06-jobs.md) R18

## Summary

Monthly pest control, weekly mowing: much of the work is the same visit again. A recurring quote
is approved once and produces a job per occurrence from the same lines, each billed when it's
completed. It's the first growth item in 06-jobs and the biggest driver of retention.

## User stories

- As an owner, I want one approval for a year of monthly treatments.
- As a client, I want to see my next treatment date and what each one costs.

## Acceptance criteria

- [ ] The quote builder can make a quote recurring: how often (weekly, every 2 weeks, monthly,
      every N months), the first date, and an end (after N times, on a date, or until stopped).
      The client page and PDF say so ("Monthly from Jan 5, 12 times; $85.00 each").
- [ ] Approval covers every occurrence at the quote's prices. Each occurrence becomes a job with
      the quote's lines at their full quantities, numbered as usual and titled "Title (3 of 12)".
      Its lines aren't claimed (JOB-09): each occurrence takes them in full.
- [ ] Jobs are made ahead (question 1), each with a visit on its date, and each follows JOB-02
      onwards: rescheduling, completion, cancelling one without touching the others.
- [ ] Each completed occurrence is billed on its own (PAY-06); NTF-04 "invoice the job" works for
      each one.
- [ ] Staff can stop the series (future occurrences not yet made won't be) and skip one occurrence.
- [ ] The quote page shows the series: done, upcoming, skipped; the client page (QTE-09) shows the
      next date, how many are done, and what's been billed.
- [ ] A recurring quote counts once toward plan usage (BIL-02), when sent.
- [ ] Office access makes and manages series; technicians see each job's visits as now (tested).
      Another business's series are not found.
- [ ] Works at 360 px. Tests: each frequency and end, month ends and DST, making jobs ahead,
      skipping, stopping, billing per occurrence, usage, roles, tenancy.

## Out of scope

- Batch invoicing of several occurrences (07-payments backlog), autopay, client self-scheduling.

## Decisions

- A recurring quote produces a job per occurrence from the same lines; each is billed when
  completed. Its own spec, the first M6 growth item in 06-jobs (owner, 2026-11-22).

## Open questions

1. How far ahead are jobs made? Recommend the next occurrence plus 60 days, made by a nightly job.
2. Who goes on the visits? Recommend the crew and arrival window set on the series, changeable
   per visit.
3. Changing the price mid-series? Recommend a new quote; the old series stops at the switch date.
4. Does an approved recurring quote expire? Recommend no: it runs until its end or is stopped.
5. A monthly occurrence on the 31st? Recommend the month's last day.
6. A fixed quote discount? Recommend it applies to each occurrence in full, as the quote shows
   prices per occurrence.
