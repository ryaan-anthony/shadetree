---
id: CLI-01
title: Client records & properties
domain: clients
milestone: M1
depends_on: [ACC-04, PLT-06]
---
# CLI-01 · Client records & properties

> Requirements: [04-clients](../../plans/04-clients.md) R1–R6

## Summary

Every quote, job and invoice is for a client at a property. Give businesses a simple, fast way
to record who their clients are and where the work happens — including clients with several
properties — without turning it into a CRM.

## User stories

- As an admin taking a phone call, I want to add a new client in seconds with just a name and a
  phone number.
- As an owner serving a property manager, I want one client with many service addresses.
- As a technician, I want access notes ("gate code 1234") attached to the property.

## Acceptance criteria

- [ ] Owners/Admins can create, edit, archive and restore clients with: display name, optional
      company name, email(s), phone(s) (at least one contact method), notes, tags, tax-exempt flag.
- [ ] A client has zero or more properties: structured address, optional label ("Rental #2"),
      access notes; one property can be marked as billing address.
- [ ] Client creation is available inline (modal/drawer) from any picker that needs a client,
      returning the new client to that flow.
- [ ] When an entered email or phone matches an existing client, the existing record is
      suggested; the user can still create a new one.
- [ ] A client page shows contact details, properties, and placeholders for related documents
      that later specs fill in (requests, quotes, jobs, invoices, balance).
- [ ] Phone numbers and emails are normalized for matching; phone links are tap-to-call.
- [ ] Clients can be deleted only when they have no documents; otherwise archive.
- [ ] Technicians cannot open client pages directly (they see client info through visits).
- [ ] Tests cover validations, duplicate suggestion, role access and tenancy.

## Out of scope

- Search/list (CLI-02), import (CLI-06), timeline (CLI-05), erasure (INS-02).
- Address autocomplete/geocoding (backlog; may be added if cheap).

## Open questions

- Multiple named contacts per client (B2B)? Recommended: primary contact + notes for now.
- Should properties support per-property contacts (e.g. tenant phone)? Recommend backlog.
