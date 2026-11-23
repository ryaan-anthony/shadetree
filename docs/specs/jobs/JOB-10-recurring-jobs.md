---
id: JOB-10
title: Recurring jobs
domain: jobs
milestone: M6
depends_on: [JOB-09, PAY-06, JOB-02, QTE-09, QTE-01]
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
      the quote's lines at full quantities, fixed discounts included, titled "Title (3 of 12)"
      (no end: "Title (3)"). Its lines aren't claimed (JOB-09): each occurrence takes them.
- [ ] Jobs are made up to 60 days ahead plus the next occurrence, each with a visit on its date
      using the series' crew and arrival window (changeable per visit), and each follows JOB-02
      onwards: rescheduling, completion, cancelling one without touching the others.
- [ ] The client gets one "Your schedule" email when a series starts, listing the coming dates.
      Made visits don't send JOB-05's "visit booked" emails or fire NTF-04 visit_scheduled; later
      changes and the usual reminders go as now. The series history records what was held back.
- [ ] Each occurrence is billed on its own, per job line (PAY-06); NTF-04 "invoice the job" works
      for each. PAY-08's progress billing and discount shares don't apply to recurring quotes.
- [ ] Staff can stop the series (no more jobs are made) and skip an occurrence.
- [ ] The quote page shows the series: done, upcoming, skipped. The client page (QTE-09) shows the
      next date, how many are done and what's been billed; the quote closes when the series ends.
- [ ] Office access makes and manages series; technicians see each job's visits as now (tested).
      Another business's series are not found.
- [ ] Works at 360 px. Tests: each frequency and end, month ends (the 31st is the month's last
      day), DST, making ahead and catching up, idempotent runs, skipping, stopping, the summary
      email and held-back notices, billing per occurrence, roles, tenancy.

## Out of scope

- Batch invoicing of several occurrences (07-payments backlog), autopay, client self-scheduling.
- Changing a running series: a new quote replaces it (decision below).

## Decisions

- A recurring quote produces a job per occurrence from the same lines; each is billed when
  completed. Its own spec, the first M6 growth item in 06-jobs (owner, 2026-11-22).
- Jobs are made for the next occurrence plus 60 days, nightly; visits take the series' crew and
  window. A price change is a new quote, the old series stopping at the switch date. An approved
  recurring quote doesn't expire. A monthly 31st is the month's last day. A fixed discount
  applies to each occurrence in full (owner, 2026-11-22).
- One "Your schedule" summary email when a series starts; after that only changes and the usual
  reminders, so there's no burst of "visit booked" emails (owner, 2026-11-22).
- No automatic job on approval (JOB-01) for a recurring quote: the series makes the jobs
  (owner, 2026-11-22).
- Deposits are allowed on recurring quotes, credited against occurrences in order
  (owner, 2026-11-22).
- Archiving the client stops new jobs (staff are told which dates are left); erasing the
  client stops the series. A series with no end titles its jobs "Title (3)" (owner, 2026-11-22).

## Implementation notes

- `job_series` (quote, frequency, first date, end, stopped at), `jobs.series_id` and
  `.occurrence` with a unique index on both, so making a job is idempotent (skip on conflict);
  skipped occurrences are stored on the series.
- A `config/recurring.yml` entry runs nightly per business under `Tenancy.with_business`,
  reporting one business's error and going on, as `AutomationsDueJob` does. The horizon is
  `business.today` + 60 days, and a missed run catches up.
