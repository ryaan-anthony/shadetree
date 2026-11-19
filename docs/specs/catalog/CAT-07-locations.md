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

- [x] Every business has a primary location, created automatically from its profile. Location
      settings stay hidden until a second location is added.
- [x] Owners/Admins can add, edit and archive locations: name, address, phone, email, time
      zone, business hours and closures (the CAT-06 settings, per location).
- [x] Members can be assigned to one or more locations; a member's default location sets the
      default for documents they create.
- [x] Requests, quotes, jobs and invoices belong to a location. The request form can be
      per-location or ask the client to choose.
- [x] Client-facing pages, PDFs and emails show that location's contact details.
- [x] Lists, the calendar and the dashboard can be filtered by location. The filter is
      remembered per member.
- [x] Scheduling warnings and reminders use the location's hours and time zone.
- [x] Document numbering stays sequential per business (an optional per-location prefix is
      allowed). *Unchanged; no per-location prefix was added.*
- [x] Multiple locations are a plan feature (BIL-01). On downgrade, existing locations stay
      readable but no new ones can be added.
- [x] Tests cover the hidden single-location experience, per-location hours and time zones,
      filtering and tenancy.

## Out of scope

- Per-location prices and taxes (CAT-08). Separate payment accounts per location. Restricting
  members to only their own location's data.

## Decisions

- **Visibility filters only** (recommendation accepted): no location-scoped permissions, and
  ACC-07 roles are unchanged.
- **One payment account per business** for now (the current model); see the open question.
- The main location's address, contact details, time zone, hours and closures stay on the
  business profile (Settings → Business and Hours), so single-location businesses see no change.
- A member's filter starts at their default location; visits keep their location's time zone.
- NTF-04's deferred "location" condition is added to automations.

## Implementation notes

- `Location` (`primary`, address, phone, email, timezone, weekly_hours, archived_at) and
  `LocationMember`; `business_users.default_location_id` and `location_filter`. `Business#primary_location`,
  `#multiple_locations?` (archived count), `BusinessUser#document_location`. Plan feature `locations`.
- `OpeningHours.new(location)`; closures without a location are the main location's. Settings →
  Locations (`Admin::LocationsController`); the Hours tab takes `?location=`.
- `AtLocation` on `ServiceRequest`, `Quote`, `Job`, `Invoice`: from the source document, else the
  member's default, else main. `#contact` (location or business) feeds the client layout, contact
  block, PDF letterhead and email footer and reply-to. Request links take `?location=<uid>`.
- `LocationFilter` (`filters_by_location Model, only:`) scopes lists, the schedule (its grid in
  that location's zone) and the dashboard. `Visit#place`, `VisitWarnings` and `VisitReminders`
  use the job's location. `MarketingHelper::COMING_SOON` no longer lists locations.
- Dev seeds: the feature comped for the demo business, a "North yard" location (Priya works
  there) with a logged request.

## Open questions

- Is one payment account per business enough, or does each branch need its own payouts?
  **(blocking for franchise-style customers)** Built with one per business for now.
