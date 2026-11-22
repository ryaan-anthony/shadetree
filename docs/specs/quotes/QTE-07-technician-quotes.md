---
id: QTE-07
title: Quotes from assigned requests
domain: quotes
milestone: M6
depends_on: [JOB-06, QTE-01, ACC-07]
---
# QTE-07 · Quotes from assigned requests

> Requirements: [05-quotes](../../plans/05-quotes.md) R20; [04-clients](../../plans/04-clients.md) R20

## Summary

After a site visit, the person who saw the job is often the best one to price it. A business can
let people without full office access draft, and optionally send, quotes for the requests
assigned to them, without seeing anything else in the office.

## User stories

- As an owner, I want my senior tech to quote what they've just looked at, so the client hears
  back the same day.
- As an owner, I want a newer tech to draft the quote but have the office check it before it's
  sent.

## Acceptance criteria

- [ ] A new role permission, "Quote assigned requests", lets a member create a quote from a
      request assigned to them, pre-filled as from the inbox (CLI-04), and edit it until sent.
      It can be given to any role (ACC-07); Owners and Admins already can.
- [ ] A second permission, "Send their own quotes", lets them send it. Without it, they mark
      the draft "Ready for review", which tells the people who manage quotes (NTF-02), and
      those people send it.
- [ ] These members see catalog items and prices while building their quotes, and the client
      and property for that request, but not other quotes, clients, invoices or the inbox.
      Direct links are refused.
- [ ] Their quotes count toward the plan's usage like any other quote (BIL-02).
- [ ] The quote records who drafted and who sent it.
- [ ] Tests cover both permissions, the review hand-off, and role and tenancy denials.

## Out of scope

- Technicians editing quotes after they're sent, or revising approved quotes.
- Technicians creating invoices (backlog).

## Decisions

- Field techs can build quotes for requests assigned to them, behind two permissions (draft;
  send), so an owner can require review (owner approved the feature set, 2026-11-21).
