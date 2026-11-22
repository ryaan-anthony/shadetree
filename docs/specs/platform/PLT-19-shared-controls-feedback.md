---
id: PLT-19
title: "Design system: tabs, toggles, search, empty states, feedback and logo upload"
domain: platform
milestone: M6
depends_on: [PLT-05, PLT-14]
---
# PLT-19 · Design system: tabs, toggles, search, empty states, feedback and logo upload

> Requirements: [01-platform](../../plans/01-platform.md) R28

## Summary

The admin audit (#314, items 9, 11, 12 and 13) found the same control built several ways. There
are four switch styles: list tabs, Schedule's dark "Color by" pills, Plan's Monthly/Yearly
toggle and Settings' page pills. The services list puts its tabs on the right and has a Search
button where other lists search as you type. Empty states range from the kit's icon-and-sentence
pattern to bare "None yet.". The logo upload is the browser's own "Choose File" control.
Quotes and Jobs show eight tabs, most at 0. Make one of each and use it everywhere.
Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want controls that do the same thing to look the same, so I learn the app once.
- As a new owner, I want empty pages to tell me what goes there and how to start.

## Acceptance criteria

- [ ] **Tabs** (switching what a list shows): one style, left-aligned under the page header,
      with counts where the list has them. The services list's Active/Archived tabs move left.
      Status tabs with a count of 0 are hidden, except "All" and the current tab.
- [ ] **Segmented control** (one choice of a few, on the same view): one kit component, used
      for Schedule's Day/Week and Color by, and Plan's Monthly/Yearly. It works by keyboard and
      announces the chosen option.
- [ ] Settings' page pills (#302) are the segmented control or tabs, not a fifth style.
- [ ] **Search:** every list searches as you type, with no Search button. Enter still submits,
      and it works without JavaScript.
- [ ] **Empty states:** the kit's pattern (icon tile, title, one sentence, at most one action,
      PLT-14) is used wherever a page or a card's main content is empty: Automations and their
      activity, Home's "Nothing booked today", My day, the data log and message templates. A
      one-line muted note stays only for a sub-list inside a card that has other content (a
      request's "Quotes: none yet").
- [ ] **Notifications:** unread items have a bold title and a dot, and read items are muted, as
      well as the "Unread" label #280 added.
- [ ] **Toast, banner, menu:** one of each in the kit, documented with when to use it. Toasts
      for results of an action (bottom centre, icon, message, Dismiss). Banners for a standing
      condition on a page (one icon, at most one link, tone from PLT-17). Menus with single-line
      items.
- [ ] **Logo upload:** a styled drop area ("Drop your logo here, or browse", with the types and
      size limit) replaces the bare file control in Branding. It works by keyboard and with a
      screen reader, and falls back to a plain file field without JavaScript.
- [ ] Branding says where the brand colour applies, for example: "Your brand colour shows on
      quotes, invoices, emails and client pages. Your admin stays Shadetree green." (see Open
      questions).
- [ ] A test fails when a list page has a search form with a submit button, or a switch that
      isn't the tabs or segmented component. A test checks each empty state in the sweep uses
      the kit pattern.
- [ ] Desktop and phone screenshots of Quotes, Services & prices, Schedule, Plan, Automations
      and Branding.

## Out of scope

- Client initials avatars in list rows (audit's token notes). Possible later, not specified
  here.
- A visible countdown on toasts. Success toasts keep disappearing after a few seconds, and
  errors stay until dismissed.
- New icons or colours.

## Open questions

- Admin colour vs business brand colour (audit item 12). **Recommendation:** the admin is
  always Shadetree's (green and navy), and the business's colour is for clients only. Branding
  says so in one sentence, and the business's initials tile in the sidebar keeps their colour.
- Hiding zero-count tabs: **Recommendation:** yes, as in the criteria. Eight tabs, mostly at 0,
  hide the ones that matter, and an empty filter isn't useful to open. "Archived" shows once
  something is archived.
- Client initials avatars in list rows: **Recommendation:** not now. They add width on phones
  for little information. Revisit after these specs ship.
