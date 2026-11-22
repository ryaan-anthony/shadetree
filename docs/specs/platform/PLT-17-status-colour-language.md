---
id: PLT-17
title: "Design system: one status colour language and one severity per event"
domain: platform
milestone: M6
depends_on: [PLT-05]
---
# PLT-17 · Design system: one status colour language and one severity per event

> Requirements: [01-platform](../../plans/01-platform.md) R26

## Summary

The admin audit (#314, item 6) found that colours don't mean one thing. Status tones are chosen
separately for quotes, jobs, invoices and requests. A request is "In progress" in amber on its
own page and grey on the client page. Partly paid is amber, as Unscheduled is. Approved and Paid
are the same green pill. One undelivered email is red on the quote page, amber on the client
page and its timeline, and plain ink in Notifications. Write the colour language down once and
draw every status pill and failure from it, using the existing tones.
Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want a colour to tell me the same thing everywhere, so I can scan a list and
  know what needs me.
- As an owner, I want a failed email to look equally serious wherever I see it.

## Acceptance criteria

- [ ] One documented map from meaning to tone, shown on the style guide with every status:
      **done or money in** (success), **waiting on the client** (info), **needs you** (warning),
      **not started or closed** (neutral), and **failed or overdue** (danger). Every quote, job,
      invoice, request, follow-up and automation status is in exactly one row (see Open
      questions for the proposed rows).
- [ ] Every status pill on staff pages comes from that one map, so the same status has the same
      tone on its own page, in lists, on the client page, on Home and in Notifications. A test
      walks every status of every record type and checks its tone against the map.
- [ ] Words carry the meaning as well as the colour: no status is shown by colour alone.
- [ ] One severity per event: an undelivered email, a failed payment or a failed automation
      step uses the danger treatment (icon, colour and wording) on the record's page, in lists,
      on the client page and its timeline, and in Notifications.
- [ ] Event icons in timelines and Notifications are neutral, except failures (danger) and
      warnings that need action (warning).
- [ ] Roles aren't statuses. Role labels on Team are plain, with no dot, and the Owner's isn't
      a different colour from other roles.
- [ ] Primary buttons stay green (PLT-14). Green pills mean only "done or money in".
- [ ] Colours come only from the theme's tokens. A test fails on a hex colour, or a raw palette
      utility, in staff views, and on a hex colour in the kit's stylesheet outside the token
      file. Today's calendar person and status colours, and the few hard-coded borders and
      hovers, move into named tokens with the same values (no visual change).
- [ ] Contrast stays AA for every pill on white and on its tint. The accessibility check passes.

## Out of scope

- New colours or a new palette. Only the existing success, info, warning, danger, neutral and
  violet tones are used.
- The calendar's per-person colours (they show who, not status).
- Client-facing pages, PDFs and emails.

## Open questions

- The proposed map, for approval. **Recommendation:**
  - success: quote Approved; job Completed; invoice Paid; request Quoted; follow-up Done;
    automation On.
  - info: quote Sent; invoice Sent and Partly paid (both wait on the client); job Scheduled and
    In progress.
  - warning: quote Changes requested; job Unscheduled; request New and In progress.
  - neutral: Draft, Expired, Void, Cancelled, Archived, Off.
  - danger: Declined, Overdue, Email not delivered, failed steps.
  - Changes from today: Partly paid amber → blue; request New blue → amber; the client page's
    grey request pill follows the map.
- Must Approved and Paid look different, as the audit says? **Recommendation:** no. Both mean
  "done" for their record, and they rarely share a list. One meaning per colour is the rule,
  and the label tells them apart. Use violet for Approved only if the owner wants them
  distinct.
- The Owner's dark role pill? **Recommendation:** plain like other roles. The Owner is already
  named in words, and a dark pill reads as a status.
