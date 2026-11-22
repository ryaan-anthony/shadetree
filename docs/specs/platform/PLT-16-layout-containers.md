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

- [ ] Two named containers are shown on the style guide:
  - **Wide**, for lists, detail pages, Home and Schedule: today's full content width.
  - **Form**, #303's form column, with an optional summary or help aside beside it on wide
    screens that stacks on phones.
  - No other page-level widths remain.
- [ ] Every staff form page uses the Form container: new and edit for clients, jobs, services,
      locations, roles, closures, tax rates and automations, the settings forms, and Help. The
      quote and invoice builders are excluded, as in PLT-14. Forms with an obvious summary
      (the quote and client a job is for) show it in the aside. The others are left-aligned
      with no blank rail.
- [ ] My day stays one column at the Form width (see Decisions).
- [ ] The guided tour's targets stay where they are and keep working. On Home that's the setup
      checklist and its steps; on My day, the Today and Coming up cards. The tour's tests pass
      unchanged.
- [ ] An integration test over the shared page list (PLT-14) fails when a page's outer
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
