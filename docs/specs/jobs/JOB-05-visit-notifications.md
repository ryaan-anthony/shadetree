---
id: JOB-05
title: Visit confirmations & reminders
domain: jobs
milestone: M3
depends_on: [JOB-02, NTF-01, PLT-12]
---
# JOB-05 · Visit confirmations & reminders

> Requirements: [06-jobs](../../plans/06-jobs.md) R13, R14

## Summary

No-shows and "I forgot you were coming" cost small businesses real money. Tell the client when a
visit is booked, changed or cancelled, and remind them the day before — with a link showing
when, where and how to reach the business.

## User stories

- As a client, I want a confirmation with the date and arrival window so that I can plan to be
  home.
- As a client, I want a reminder the day before.
- As an owner, I want to control which of these messages go out.

## Acceptance criteria

- [ ] When a visit is scheduled, rescheduled or cancelled, the client receives an email (if the
      client has an email) using the business-branded layout.
- [ ] A reminder email is sent the day before the visit at a sensible local time (business time
      zone), only for visits still scheduled.
- [ ] Each email links to a client visit page (PLT-12 link) showing business, date, time or
      window, property address, visit instructions intended for the client, and business
      contact options. Cancelled visits show as cancelled.
- [ ] Owners/Admins can turn each message type on/off in settings, and skip notification for an
      individual change ("don't notify client").
- [ ] Rapid successive edits don't spam the client (changes within a short window are coalesced).
- [ ] Sent messages are recorded per NTF-01 and visible on the job.
- [ ] Tests cover timing (time zones, DST), suppression settings, coalescing and link scope.

## Out of scope

- SMS confirmations/reminders, "on my way" messages, client confirmation/reschedule requests
  (backlog).

## Open questions

- Reminder lead time: fixed day-before vs configurable hours? Recommend fixed at launch.
- Should the client be able to reply "can't make it" from the visit page? Recommend backlog.
