---
id: CAT-06
title: Business hours & closures
domain: catalog
milestone: M3
depends_on: [CAT-01]
---
# CAT-06 · Business hours & closures

> Requirements: [03-catalog](../../plans/03-catalog.md) R15

## Summary

Scheduling needs to know when the business normally works and when it's closed. Capture weekly
hours and one-off closures simply, so the calendar can shade off-hours and warn about visits
scheduled on closed days, and so self-booking can build on it later.

## User stories

- As an owner, I want to set my normal working hours so that my calendar shows them.
- As an owner, I want to mark holidays and vacation so that nobody books work then.

## Acceptance criteria

- [x] Owners/Admins set, per weekday, closed or open with a start and end time (one range per
      day is enough at launch); a "weekdays 8–5" quick preset exists. *Settings → Hours. Until
      hours are set, every day counts as open, so nothing is shaded or warned about.*
- [x] Owners/Admins add, edit and remove closures: a date or date range, optional partial-day
      hours, and a reason. *A closure can also repeat every year (decided, see below).*
- [x] Hours and closures are interpreted in the business's time zone.
- [x] A shared query answers "is the business open at this time/date?" for other features
      (JOB-02 warnings, JOB-03 shading, backlog self-booking). *`OpeningHours`: `open_at?`,
      `open_on?`, and `day(date)` with its open periods and closures.*
- [x] Optional: business hours display on client-facing pages (e.g. contact block).
- [x] The existing hours tab is replaced; its data (if any) is migrated or reset per PLT-07.
      *There was no hours tab or data left after PLT-07; Hours is a new settings tab.*
- [x] Tests cover overnight edge cases (rejected or supported, decided), DST and tenancy.
      *Overnight hours and closures are rejected.*

## Out of scope

- Per-member availability and time off (backlog with self-scheduling).
- Hours per location — CAT-07 extends these same settings per location.

## Open questions

- ~~Support split shifts (two ranges per day)?~~ *Decided: not at launch, one range per day.*
- ~~Recurring yearly closures?~~ *Decided: supported. A closure can repeat every year on the
  same dates (it can wrap the new year); holidays that move, like Thanksgiving, are re-added.*
