---
id: PLT-05
title: "UI foundation: build pipeline, layouts, components"
domain: platform
milestone: M0
depends_on: [PLT-01]
---
# PLT-05 · UI foundation: build pipeline, layouts, components

> Requirements: [01-platform](../../plans/01-platform.md) R15, R16, R21

## Summary

Styles are currently loaded from a CDN at runtime with configuration copied into each layout.
Replace this with a compiled, cache-friendly stylesheet, a single set of design tokens, three
purpose-built layouts, and a small kit of reusable UI building blocks so feature teams build
consistent screens quickly.

## User stories

- As a developer, I want ready-made buttons, fields, lists, cards and empty states so that a
  new screen takes minutes, not hours.
- As a technician on a phone, I want the app navigation to work well on a small screen.
- As a client, I want business pages that load instantly and look like the business.

## Acceptance criteria

- [ ] No runtime CDN dependency for CSS or JS; styles are compiled at build time and served
      with long-lived caching.
- [ ] Design tokens (colors including semantic success/warning/danger, type scale, spacing,
      radii) are defined once and used everywhere; the existing palette is the starting point.
- [ ] Three layouts exist: **marketing/public**, **staff app** (responsive; sidebar on desktop,
      bottom or drawer navigation on mobile; business switcher; flash messages), and
      **client-facing** (minimal, brandable with a business logo and color, no staff chrome).
- [ ] A component kit covers: buttons (primary, secondary, danger, link), form fields with
      labels/help/errors, select, checkbox, date/time input, money input, table/list with empty
      state, card, badge/status pill, modal/confirm, pagination, toast/flash.
- [ ] A living style-guide page (development-only) shows every component and state.
- [ ] Existing pages are migrated to the new layouts with no visual regressions of note.
- [ ] Components meet WCAG 2.1 AA contrast and are keyboard accessible.

Visual reference: [`docs/mockups/design-system.html`](../../mockups/design-system.html) and the
screens in [`docs/mockups`](../../mockups/README.md). Treat them as design direction, not code.

## Implementation notes

Conventions from the QA/accessibility audit (#274), for every staff page:

- **Landmarks:** the app layout has a `<header>` (top bar), the sidebar's `<nav>`, `<main>`, and
  the sidebar's foot (you, sign out, legal links) as the `<footer>`; the operator console too.
- **Headings:** one H1 per page (`page_header`). Empty states are H2 (`empty_state`),
  `level: 3` inside a titled card (its title is an H2), `level: 1` when they are the page.
- **Names:** a link or button repeated down a page names its row ("Download CSV: Clients",
  "Add here: Lawn care"), starting with its visible words. Tabs mark the current one with
  `aria-current="page"`; filter buttons use `aria-pressed`.
- **Status messages:** error toasts are `role="alert"`; other toasts are read through
  `#announcer`, a polite live region kept across Turbo visits (joined when several arrive,
  emptied after a few seconds, silent on Back). `role="status"` only on content that updates.
- **Dates:** records, documents and emails always carry the year. Pages about now (today,
  this week, what's coming up) leave it off while it's this year (`friendly_date`, or
  `local_date`/`local_time` with `year: :auto`); today's and this week's pages never show it.
- **Time zones:** a page with times on one day names the zone once ("Times in Eastern Time
  (US & Canada)"), never on each time.
- **Contrast:** `muted` is #5e6d82 (was #64748b, 4.44:1 on the page background): 5.27:1 on
  white, 4.92 on canvas, 4.77 on sunken. `faint` is never text.
- **Checks:** `test/system/accessibility_test.rb` runs axe-core (WCAG 2.1 A/AA) on key pages.
- #289: every Turbo form's submit button says what it's doing while it runs ("Creating…",
  "Sending…"), from one hook (`submitting.js`); `data-turbo-submits-with` overrides it.
- #289: `.form-split` puts a form (up to 42rem) beside a 20rem summary card on wide screens and
  stacks them on phones; used by Schedule a visit (the job), Record a payment (the invoice) and
  Log a request (what happens next).

## Out of scope

- Brand color application per business beyond the client layout hook (CAT-02).
- Marketing page redesign (MKT-01).

## Open questions

- ~~Icon set: keep the current one or switch?~~ Resolved: keep Feather, rendered as inline SVG
  on the server (no icon font or script).
- ~~Dark mode: not planned; confirm.~~ Resolved: not planned. Tokens are CSS variables, so it
  can be added later without touching components.
