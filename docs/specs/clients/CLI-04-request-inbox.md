---
id: CLI-04
title: Request inbox
domain: clients
milestone: M2
depends_on: [CLI-03, QTE-01]
---
# CLI-04 · Request inbox

> Requirements: [04-clients](../../plans/04-clients.md) R14, R15, R16

## Summary

All incoming work requests — from the public form or entered by staff after a phone call — land
in one inbox where the team can see what's new, turn a request into a quote in one tap, and
archive what isn't going anywhere.

## User stories

- As an owner, I want to see new requests at a glance so that I respond before competitors do.
- As an admin, I want to log a phone request so that it doesn't live on a sticky note.
- As an owner, I want to create a quote from a request without retyping anything.

## Acceptance criteria

- [ ] Requests have statuses New, In progress, Quoted, Archived; status changes automatically to
      Quoted when a quote is created from it, and can be changed manually otherwise.
- [ ] The inbox lists requests newest first with client, property, requested services, age and
      status; filters by status; a badge in navigation shows the New count.
- [ ] Opening a request marks who viewed it and shows all submitted details and photos.
- [ ] Owners/Admins can create a request manually (client picker/inline create, property,
      services, notes, source such as phone/email/walk-in).
- [ ] "Create quote" opens the quote builder pre-filled with client, property, requested
      services as line items, and request photos available as attachments; the request links to
      every quote created from it.
- [ ] Requests appear on the client's page.
- [ ] Internal notes can be added to a request.
- [ ] Technicians have no access; tenancy and role tests exist.

## Out of scope

- Assignment of requests to members, lead sources reporting, SLAs (backlog).

## Open questions

- Should "In progress" exist, or is New/Quoted/Archived enough? Recommend keeping it for
  requests needing a site visit before quoting.
