---
id: PLT-19
title: "Design system: tabs, segmented controls, search and menus"
domain: platform
milestone: M6
depends_on: [PLT-05, PLT-14]
---
# PLT-19 · Design system: tabs, segmented controls, search and menus

> Requirements: [01-platform](../../plans/01-platform.md) R28

## Summary

The admin audit (#314, items 9 and 13) found the same control built several ways:
- Five switch styles: list tabs, Schedule's dark "Color by" pills, Plan's Monthly/Yearly
  toggle, Schedule's Day/Week tabs and Settings' page pills (#302).
- The services list puts its tabs on the right and has a Search button, where other lists
  search as you type.
- Quotes and Jobs show eight tabs, most at 0.
- The quote menu's "Duplicate for another client" wraps.

Make one of each and use it everywhere. Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want controls that do the same thing to look the same, so I learn the app once.

## Acceptance criteria

- [ ] **Tabs** switch what a list shows. One style, left-aligned under the page header, with
      counts where the list has them. The services list's Active/Archived tabs move left.
- [ ] Status tabs with a count of 0 are hidden, except "All" and the current tab. "Archived"
      shows once something is archived.
- [ ] **Segmented control** picks one of a few options on the same view. It's one kit
      component, with Plan's white-pill look, used for Schedule's Day/Week and Color by and
      Plan's Monthly/Yearly. It works by keyboard and announces the chosen option.
- [ ] Settings' page pills (#302) become the segmented control or tabs, not a separate style.
- [ ] **Search:** every list searches as you type, with no Search button. Enter still submits,
      and it works without JavaScript.
- [ ] **Menus:** one kit menu (white card, shadow, card radius). It is as wide as its longest
      item, so items never wrap ("Duplicate for another client" fits).
- [ ] The guided tour's targets keep working, including the sidebar's Settings link that opens
      the settings pills, and the tour's tests pass unchanged.
- [ ] Integration tests over the shared page list (PLT-14) fail when a list page has a search
      form with a submit button, or a switch that isn't the tabs or segmented component.
- [ ] Desktop (1280) and phone (390) screenshots of Quotes, Services & prices, Schedule, Plan
      and a settings page.

## Out of scope

- New icons or colours.
- Initials avatars in list rows (see Decisions).

## Decisions

- Zero-count status tabs are hidden, except "All" and the current one (owner, 2026-11-22).
- No initials avatars in client rows for now. They take width on phones for little
  information. Revisit after these specs ship (owner, 2026-11-22).
