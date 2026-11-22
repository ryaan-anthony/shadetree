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

- [x] A new role permission, "Quote assigned requests", lets a member create a quote from a
      request assigned to them, pre-filled as from the inbox (CLI-04), and edit it until sent.
      It can be given to any role (ACC-07); Owners and Admins already can.
      *From a done follow-up on their day; theirs to edit (not delete) until it's sent. Owners and
      Admins have both permissions; others get them through a custom role.*
- [x] A second permission, "Send their own quotes", lets them send it. Without it, they mark
      the draft "Ready for review", which tells the people who manage quotes (NTF-02), and
      those people send it.
      *The office sees who marked it, and when, on the draft, then sends it as usual.*
- [x] These members see catalog items and prices while building their quotes, and the client
      and property for that request, but not other quotes, clients, invoices or the inbox.
      Direct links are refused.
      *The client stays the request's; any other quote is not found; office pages stay refused.*
- [x] Their quotes count toward the plan's usage like any other quote (BIL-02).
- [x] The quote records who drafted and who sent it.
      *Drafted by (on the draft for office staff, and in its history), marked ready, and sent by.*
- [x] Tests cover both permissions, the review hand-off, and role and tenancy denials.

## Out of scope

- Technicians editing quotes after they're sent, or revising approved quotes.
- Technicians creating invoices (backlog).

## Implementation notes

- Permissions quote_requests and send_own_quotes (docs/plans/02-accounts.md). OwnQuoteAccess
  limits these members to drafts they made from requests; "Ready for review" records an event
  and tells the office (NTF-02 "A quote is ready to check").
- Dev seeds: Riley (senior@example.com), a "Senior tech", has a draft marked ready for review.

## Decisions

- Field techs can build quotes for requests assigned to them, behind two permissions (draft;
  send), so an owner can require review (owner approved the feature set, 2026-11-21).
- The built-in Technician role gets neither; a business gives them through a custom role.
- Deleting a draft stays with the office.
- Changing a draft after marking it ready takes it back until it's marked again (proposed,
  pending the owner).
- Someone sending their own quote sends to the client's emails on file, and can't send a copy
  of an approved one; anything else goes through the office.
- Drafts someone made from requests while they were office staff stay theirs if their role
  later becomes quote-only (accepted for now).
