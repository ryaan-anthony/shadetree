---
id: JOB-04
title: Technician day view
domain: jobs
milestone: M3
depends_on: [JOB-02]
---
# JOB-04 · Technician day view

> Requirements: [06-jobs](../../plans/06-jobs.md) R10, R11, R12

## Summary

Technicians need exactly one screen: where am I going today, what do I need to know, and how do
I mark it done. Build a fast, phone-first "My day" that works with gloves on and a weak signal.

## User stories

- As a technician, I want to open the app and see today's visits in order so that I know my day.
- As a technician, I want to tap the address for directions and tap to call the client.
- As a technician, I want to add notes and photos and mark the visit complete on site.
- As an owner, I want to know when work actually started and finished.

## Acceptance criteria

- [x] Technicians land on "My day" after sign-in: today's assigned visits in time order, then
      upcoming days; Owners/Admins can also open their own "My day".
      *Then anything still open from earlier, then the next 14 days.*
- [x] Each visit shows client name, time/window, property address (opens the device's maps app),
      access notes, tap-to-call and tap-to-text, job instructions and line items (names and
      quantities; prices hidden unless the business allows technicians to see prices).
      *The address opens Google Maps directions (the app where installed).*
- [ ] Technicians can mark Start and Complete (timestamps recorded), add notes, and attach
      photos from the camera (count/size limited; uploads tolerate poor connections with clear
      progress and retry).
- [x] Completing the last visit of a job notifies Owners/Admins that the job is ready to invoice.
- [x] Technicians can only see visits assigned to them and the client/property info for those
      visits; direct URLs to anything else are denied.
- [ ] The view is fast (< 1 s on 4G), large-tap-target friendly, and installable to the home
      screen.
- [x] A business setting controls whether technicians see prices.
      *Settings → Documents → Jobs; off by default. Owners and Admins always see them.*
- [ ] Tests cover visibility rules, start/complete, photo upload and tenancy.

## Out of scope

- Offline mode, time tracking, materials, on-site signature, "on my way" texts (backlog).
- Technicians creating quotes or invoices (backlog toggle).

## Open questions

- Photo storage/retention per plan (BIL-01) and storage ADR (PLT-01).
- ~~Should a technician be able to un-complete a visit?~~ *Decided: yes, the same day (business time).*
