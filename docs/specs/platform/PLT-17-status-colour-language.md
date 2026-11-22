---
id: PLT-17
title: "Design system: one status colour language and one severity per event"
domain: platform
milestone: M6
depends_on: [PLT-05, PLT-14]
---
# PLT-17 · Design system: one status colour language and one severity per event

> Requirements: [01-platform](../../plans/01-platform.md) R26

## Summary

The admin audit (#314, item 6) found that colours don't mean one thing:
- Status tones are chosen separately per record type. A request's "In progress" is amber on its
  own page and grey on the client page.
- Partly paid is amber, the same as Unscheduled.
- One undelivered email is red, amber or plain ink depending on the page.

Write the colour language down once and draw every status pill and failure from it, using the
existing tones. Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want a colour to tell me the same thing everywhere, so I can scan a list.
- As an owner, I want a failed email to look equally serious wherever I see it.

## Acceptance criteria

- [ ] One documented map from meaning to tone (Decisions), shown on the style guide with every
      status: quotes, jobs, visits, invoices, requests, follow-ups, automations and their runs,
      support tickets, and the quota meter's states (BIL-06).
- [ ] Every status pill on staff pages comes from that one map, so the same status has the same
      tone on its own page, in lists, on the client page, on Home, in My day and in
      Notifications. A test walks every status of every record type and checks its tone
      against the map.
- [ ] The calendar's "Color by status" follows the map. In progress changes from amber to the
      info tint, a visual change on the calendar only. Scheduled keeps its lighter sky tint so
      the two stay apart, and the legend names both.
- [ ] Words carry the meaning as well as the colour: no status is shown by colour alone.
- [ ] One severity per event. An undelivered email, a failed payment or a failed automation
      step gets the danger treatment (icon, colour and wording) on the record's page, in
      lists, on the client page and its timeline, and in Notifications. Other event icons are
      neutral.
- [ ] Role labels on Team are plain with no dot, the Owner's included.
- [ ] Colours come only from the theme's tokens. A test scans the source of the staff views,
      helpers and the kit's stylesheet, outside the token file. It ignores comments, allows
      white, and exempts the brand helper and Branding's presets (business colours are data).
      It fails on a hex colour, an arbitrary colour value or a raw palette class.
- [ ] Hard-coded colours move into tokens with the same values (no visual change):
  - the calendar's person and status colours;
  - the kit's hard-coded borders and hovers;
  - the support message's internal-note tint;
  - the setup checklist's step border;
  - the sidebar foot's text;
  - Branding preview's client background.
- [ ] Contrast stays AA for every pill on white and on its tint, and the accessibility check
      passes.
- [ ] Desktop (1280) and phone (390) screenshots of Quotes, Jobs, Invoices, a client page,
      Schedule (by status) and Notifications.

## Out of scope

- New colours. Only the existing success, info, warning, danger, neutral and violet tones.
- The calendar's per-person colours (they show who, not status). Client-facing pages and PDFs.

## Decisions

- The map (owner, 2026-11-22):
  - **success** (done or money in): quote Approved; job and visit Completed; invoice Paid;
    request Quoted; follow-up Done; automation On; run Done; ticket Resolved.
  - **info** (waiting on someone else): quote Sent; invoice Sent and Partly paid; job and visit
    Scheduled and In progress; run Waiting; ticket Open.
  - **warning** (needs you): quote Changes requested; job Unscheduled; request New and In
    progress; ticket Waiting on you; meter "Nearly used".
  - **neutral** (not started or closed): Draft, Expired, Void, Cancelled, Archived, Off,
    Skipped, and the meter's normal state.
  - **danger** (failed or overdue): Declined, Overdue, Email not delivered, failed steps and
    runs, meter "Limit reached".
- Approved and Paid both stay green. Both mean "done", and the label tells them apart (owner,
  2026-11-22).
- The Owner's role pill is plain like other roles (owner, 2026-11-22).
- Visits, automation runs, support tickets and the meter go into the map with their current
  tones, so nothing changes (review of #332).
- The calendar's In progress follows the map and turns from amber to info (review of #332
  asked for one choice; coordinator to confirm).
