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

- [ ] Owners/Admins set, per weekday, closed or open with a start and end time (one range per
      day is enough at launch); a "weekdays 8–5" quick preset exists.
- [ ] Owners/Admins add, edit and remove closures: a date or date range, optional partial-day
      hours, and a reason.
- [ ] Hours and closures are interpreted in the business's time zone.
- [ ] A shared query answers "is the business open at this time/date?" for other features
      (JOB-02 warnings, JOB-03 shading, backlog self-booking).
- [ ] Optional: business hours display on client-facing pages (e.g. contact block).
- [ ] The existing hours tab is replaced; its data (if any) is migrated or reset per PLT-07.
- [ ] Tests cover overnight edge cases (rejected or supported, decided), DST and tenancy.

## Out of scope

- Per-member availability and time off (backlog with self-scheduling).
- Recurring annual closures (e.g. every Dec 25) — see open question.

## Open questions

- Support split shifts (two ranges per day)? Recommend not at launch.
- Recurring yearly closures? Recommend backlog; users re-add holidays yearly.
