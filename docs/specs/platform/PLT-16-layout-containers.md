---
id: PLT-16
title: "Design system: two layout containers"
domain: platform
milestone: M6
depends_on: [PLT-05, PLT-14, PLT-15]
---
# PLT-16 · Design system: two layout containers

> Requirements: [01-platform](../../plans/01-platform.md) R25

## Summary

The admin audit (#314, item 4) found page widths changing by page type, with forms in narrow
columns beside empty space. #301 rebuilt Home to fill the screen, and #303 gave three long forms
a summary beside them. Other pages still use about seven ad-hoc widths. Define two containers
and use only those. Repeated facts on detail pages are PLT-20.
Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner on a wide screen, I want pages to use the space for my work, not grey margins.
- As an owner, I want every form to sit in the same place, so pages don't jump as I move.

## Acceptance criteria

- [x] Two named containers are shown on the style guide:
  - **Wide**, for lists, detail pages, Home and Schedule: today's full content width.
  - **Form**, #303's form column, with an optional summary or help aside beside it on wide
    screens that stacks on phones.
  - No other page-level widths remain.
- [x] Every staff form page uses the Form container: new and edit for clients, jobs, services,
      locations, roles, closures, tax rates and automations, the settings forms, and Help. The
      quote and invoice builders are excluded, as in PLT-14. Forms with an obvious summary
      (the quote and client a job is for) show it in the aside. The others are left-aligned
      with no blank rail.
- [x] My day stays one column at the Form width (see Decisions).
- [x] The guided tour's targets stay where they are and keep working. On Home that's the setup
      checklist and its steps; on My day, the Today and Coming up cards. The tour's tests pass
      unchanged.
- [x] An integration test over the shared page list (PLT-14) fails when a page's outer
      wrapper has a width limit other than the two containers. Widths inside cards, dialogs
      and fields aren't checked.
- [ ] Desktop (1280 and 1920) and phone (390) screenshots of a list, a detail page and three
      forms (one with an aside).

## Out of scope

- Each fact once on detail pages, and rail density (PLT-20).
- Home's layout (#301). The calendar grid's own layout.
- Client-facing pages, PDFs and emails.

## Decisions

- The Form container is left-aligned, on the same left edge as list pages, with the aside to
  its right (owner, 2026-11-22).
- My day stays one column. It's the technician's phone page, and office staff reach it from
  Home's "Your day" (#301). Wide is for office pages (owner, 2026-11-22).

## Implementation notes

- My day's visit and request pages, and the schedule's visit and follow-up panels opened as pages,
  stay one column at the Form width too: they're the same technician pages (following the My day
  decision).
- Lists that sit under Settings (taxes, locations, roles, messages, automations) are Wide like
  every list; the settings pages with a form or account details (business tabs, hours, notification
  settings, payments, plan, starter services) use Form.
- Wide is the content area itself (`.content`, up to 80rem): a page adds no width of its own.
  Form is `.form-split`, #303's column, now 42rem everywhere; with a `.form-split-aside` child it
  becomes the column plus a 20rem aside from 1280px, stacked before or after it (page order) below.
  Both are on the style guide's "Page containers" section.
- Edit job shows the client (with phone) and the quote it came from in the aside; the form's
  read-only "Client" line moved there. New job has no aside (the client is picked in the form).
- Branding's form and preview use the Form container (preview in the aside); the set-up, suspended
  and not-allowed pages moved from centred cards to the Form column, and the operator console's
  edit cards to Form as well. The console's own layout width (72rem) is its Wide; its two-factor
  sign-in pages stay centred like sign-in.
- The design-system sweep's `page_width_is_a_container` check flags any `max-w-*` outside cards,
  dialogs, menus, tables and fields (a block holding controls and no card, such as a search box).
  `max-w-prose` is a paragraph's measure. The shared page list gains edit location, edit closure,
  edit client note, edit payment and delete role.
- Dev seeds: none new. The demo's jobs from approved quotes show the Edit job aside.

