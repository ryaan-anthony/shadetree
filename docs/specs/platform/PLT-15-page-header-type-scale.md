---
id: PLT-15
title: "Design system: one page header and a locked type scale"
domain: platform
milestone: M6
depends_on: [PLT-05, PLT-14]
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
      Notifications. It never shows the page title, at any width. The unused slot for
      page-specific top-bar actions is removed. The browser tab title is unchanged.
- [ ] Every staff page opens with the kit's page header: one H1, an optional one-line subtitle,
      and the page's actions (PLT-14) on the right, wrapping below on phones. The quote page's
      action row matches the other detail pages.
- [ ] The type scale is defined once, as named steps, and shown on the style guide: page title,
      section title, card title, body, small and table header, with the values in the
      Decisions. Headings and titles use only these steps.
- [ ] A sentence is never a heading. The sent panel on the quote and invoice pages is titled
      "Sent". The date and sender ("Nov 22, 2026, 2:38 PM by Dana Whitaker") are body text
      under the title.
- [ ] On the staff quote page, the document card doesn't repeat the page heading as a second
      large title (PLT-20).
- [ ] Settings pages keep "Settings" as the H1, with the group and page shown by the current
      tab and pill (#302). Nothing on the page calls it by another name.
- [ ] Schedule: the H1 is "Schedule". The subtitle starts with the range and keeps the view
      and the zone: "November 16 – 22, 2026 · Week view · Times in Eastern Time (US &
      Canada)". The browser tab title is unchanged.
- [ ] The guided tour (ACC-08) still works:
  - the top bar's Help button keeps its tour target;
  - the H1 stays inside the page's main region, where the tour and tips look for it;
  - the sidebar links keep their tour targets.
  - The tour's integration and browser tests pass unchanged.
- [ ] Headings stay in order with no skipped levels, and the accessibility check still passes.
- [ ] Integration tests over the shared page list (PLT-14) fail when:
  - the top bar contains the H1's text;
  - a page doesn't have exactly one H1;
  - an H2 or H3 contains a date;
  - the sent panel's title isn't the fixed label.
  - Record names used as headings (quote titles, client names) are exempt from length rules.
- [ ] Desktop and phone screenshots of Home, Schedule, a settings page and the quote page.

## Out of scope

- A new font, new sizes or new weights.
- Marketing and client-facing pages, which have their own headers.
- Global search in the top bar.

## Decisions

- The scale locks today's values (owner, 2026-11-22):
  - page title: 22 px bold, or 19 px on phones;
  - section and card titles: 15 px at weight 650;
  - body: 14 px;
  - small text: 13 px;
  - table headers: 13 px semibold, muted.
- Schedule's H1 is "Schedule", with the range as the subtitle (owner, 2026-11-22). This
  supersedes #274's decision that the schedule heading includes "Schedule" and the year
  (owner, 2026-11-21). The year still shows, in the subtitle.
- The top bar never shows the page title, even on phones after scrolling (owner, 2026-11-22).
