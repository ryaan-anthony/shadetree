---
id: CAT-07
title: Locations
domain: catalog
milestone: M5
depends_on: [CAT-06, JOB-03, BIL-01]
---
# CAT-07 · Locations

> Requirements: [03-catalog](../../plans/03-catalog.md) R16, R17

## Summary

Some businesses run more than one base — two branches of a cleaning company, or a landscaper
with a north and south yard. Let a business add locations, each with its own address, contact
details, time zone, hours and team, and filter work by location — while single-location
businesses never see any of it.

## User stories

- As an owner with two branches, I want each branch's quotes and calendar kept apart so that
  each manager sees their own work.
- As a client, I want my quote to show the branch I'm dealing with, with its phone number.
- As a solo operator, I don't want to see anything about locations.

## Acceptance criteria

- [ ] Every business has a primary location, created automatically from its profile. Location
      settings stay hidden until a second location is added.
- [ ] Owners/Admins can add, edit and archive locations: name, address, phone, email, time
      zone, business hours and closures (the CAT-06 settings, per location).
- [ ] Members can be assigned to one or more locations; a member's default location sets the
      default for documents they create.
- [ ] Requests, quotes, jobs and invoices belong to a location. The request form can be
      per-location or ask the client to choose.
- [ ] Client-facing pages, PDFs and emails show that location's contact details.
- [ ] Lists, the calendar and the dashboard can be filtered by location. The filter is
      remembered per member.
- [ ] Scheduling warnings and reminders use the location's hours and time zone.
- [ ] Document numbering stays sequential per business (an optional per-location prefix is
      allowed).
- [ ] Multiple locations are a plan feature (BIL-01). On downgrade, existing locations stay
      readable but no new ones can be added.
- [ ] Tests cover the hidden single-location experience, per-location hours and time zones,
      filtering and tenancy.

## Out of scope

- Per-location prices and taxes (CAT-08). Separate payment accounts per location. Restricting
  members to only their own location's data.

## Open questions

- Should members be restricted to their own location's data (location-scoped permissions)?
  This interacts with ACC-07. Recommend visibility filters first, restrictions later.
- Is one payment account per business enough, or does each branch need its own payouts?
  **(blocking for franchise-style customers)**
