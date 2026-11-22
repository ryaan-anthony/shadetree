---
id: PLT-15
title: "Design system: one page header and a locked type scale"
domain: platform
milestone: M6
depends_on: [PLT-05]
---
# PLT-15 · Design system: one page header and a locked type scale

> Requirements: [01-platform](../../plans/01-platform.md) R24

## Summary

The admin audit (#314, items 2 and 3) found that every page repeats its title in the top bar
just above an identical heading. Settings pages say "Payments" in the bar and "Settings" in the
heading. On the quote page the document title is as large as the page heading and repeats it,
and "Sent … by …" is set as a heading. Lock the type scale the app already uses and give every
page one header: a heading, one line under it, and actions on the right. Nothing above it but
global controls. Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want each page to say what it is once, so the page starts with its content.
- As a screen-reader user, I want headings that match what the page looks like.

## Acceptance criteria

- [ ] The top bar holds only global controls: the menu button on phones, Help and
      Notifications. It never shows the page title, at any width. The browser tab title is
      unchanged.
- [ ] Every staff page opens with the kit's page header: one H1, an optional one-line subtitle,
      and the page's actions (PLT-14) on the right, wrapping below on phones. The quote page's
      action row matches the other detail pages.
- [ ] The type scale is defined once, as named steps, and shown on the style guide: page title,
      section title, card title, body, small or caption, and table header. Its values are the
      ones in use today (see Open questions). Headings and titles use only these steps.
- [ ] A sentence is never a heading. "Sent Nov 22, 2026, 2:38 PM by …" on the quote and invoice
      pages becomes body text under a short card title.
- [ ] The staff quote page doesn't repeat the page heading as a second, equally large title in
      the document card. The document title there is a card title or is left out (PLT-16).
- [ ] Settings pages keep "Settings" as the H1, with the group and page shown by the current
      tab and pill (#302). Nothing on the page calls it by another name.
- [ ] Headings stay in order with no skipped levels. The accessibility check still passes on
      every page in its sweep.
- [ ] A test visits the same sweep of staff pages and fails when the top bar contains the H1's
      text, when a page has other than one H1, or when a heading's text is longer than one
      short line (60 characters).
- [ ] Desktop and phone screenshots of Home, Schedule, a settings page and the quote page.

## Out of scope

- A new font, new sizes or new weights. The audit says to keep the font.
- Marketing and client-facing pages. They have their own headers.
- A global search in the top bar (not built, and not proposed by the audit).

## Open questions

- Which values does the scale lock? **Recommendation:** today's: page title 22 px bold (19 px
  on phones), section and card titles 15 px semibold, body 14 px, small text 13 px, table
  headers 13 px semibold muted. These are close to the audit's example (24/16/14/14/12/12),
  and keeping them avoids a visual change. Only off-scale one-offs move.
- Schedule's heading: the audit wants "Schedule" in the H1 and the dates beside the date
  controls. #274 (owner, 2026-11-21) decided "the schedule heading includes 'Schedule' and the
  year". **Recommendation:** H1 "Schedule", with the range ("November 16 – 22, 2026") as the
  subtitle next to the Today/arrows controls, so the year still shows. This revises the #274
  decision and needs the owner's yes. Otherwise keep the H1 and only drop the colon form
  ("Schedule, November 16 – 22, 2026").
- Phones: should the top bar show the title once the H1 has scrolled away? **Recommendation:**
  no. Keep the bar for global controls only. That's simpler and identical at every width.
