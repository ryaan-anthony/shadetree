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

- [x] **Tabs** switch what a list shows. One style, left-aligned under the page header, with
      counts where the list has them. The services list's Active/Archived tabs move left.
- [x] Status tabs with a count of 0 are hidden, except "All" and the current tab. "Archived"
      shows once something is archived.
- [x] **Segmented control** picks one of a few options on the same view. It's one kit
      component, with Plan's white-pill look, used for Schedule's Day/Week and Color by and
      Plan's Monthly/Yearly. It works by keyboard and announces the chosen option.
- [x] Settings' page pills (#302) become the segmented control or tabs, not a separate style.
- [x] **Search:** every list searches as you type, with no Search button. Enter still submits,
      and it works without JavaScript.
- [x] **Menus:** one kit menu (white card, shadow, card radius). It is as wide as its longest
      item, so items never wrap ("Duplicate for another client" fits).
- [x] The guided tour's targets keep working, including the sidebar's Settings link that opens
      the settings pills, and the tour's tests pass unchanged.
- [x] Integration tests over the shared page list (PLT-14) fail when a list page has a search
      form with a submit button, or a switch that isn't the tabs or segmented component.
- [ ] Desktop (1280) and phone (390) screenshots of Quotes, Services & prices, Schedule, Plan
      and a settings page.

## Implementation notes

- Kit: `ControlsHelper#tabs`, `#segmented_control` and `#menu`, each on the style guide. Tabs and
  the segmented control come as links (`href:`), a filter form's buttons (`name:`) or radios
  (`radio:`). Tabs take `counts:` and hide zeros except `keep:` and the current tab.
- The menu is a disclosure (`aria-expanded`, `aria-controls`, no ARIA menu roles): arrow keys,
  Home/End, Escape back to the button, Tab moves on and closes it. It's `max-content` wide and
  shifts back on screen on phones. The business switcher keeps its own trigger with the same ARIA.
- Lists put search first, then tabs. Services search into a frame (GET, so Enter works without
  JavaScript); its tabs sit in the frame to keep the search. Requests post to `#search` like
  Quotes, by client or description, within the tab and assignee.
- Each list has one status region outside its results frame (`results_status`), announcing
  every render. A pressed filter tab hides a leftover zero-count one.
- Settings keep their group tabs; a group's pages and Hours' locations are segmented controls,
  which wrap rather than scroll. The ops console's message tabs use the kit (all shown).
- `design_system_test.rb` adds `kit_menus`, `search_as_you_type`, `one_switch_style` and
  `no_empty_tabs`; `kit_controls_test.rb` drives them by keyboard with axe.
- Dev seeds: an archived "Snow plowing" service, so Services shows its Archived tab.

## Out of scope

- New icons or colours.
- Initials avatars in list rows (see Decisions).

## Decisions

- Zero-count status tabs are hidden, except "All" and the current one (owner, 2026-11-22).
- Requests get the same search-as-you-type box as the other lists (owner, 2026-11-23).
- No initials avatars in client rows for now. They take width on phones for little
  information. Revisit after these specs ship (owner, 2026-11-22).
