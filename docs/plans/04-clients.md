# 04 · Clients & requests

## Purpose

Keep a lightweight record of who the business works for and where, and capture new work
requests from the public without phone tag. This is "CRM-lite": enough to quote, schedule and
invoice — not a sales pipeline.

## Current state

Nothing implemented. A `customer_notification_preferences` table references end clients as
users, which conflicts with the "clients never sign in" principle.

## Requirements

### Client records
- **R1** A client has a display name (person or company), optional company name, one or more
  contact methods (email, phone — at least one required), notes, and optional tags.
- **R2** A client has zero or more properties (service addresses). One may be the billing
  address. Each property can carry access notes ("gate code", "dog in yard").
- **R3** Clients can be created inline while creating a request, quote or job — no detour.
- **R4** Duplicate detection: when entering a client whose email or phone matches an existing
  one, suggest the existing record.
- **R5** Clients can be archived (hidden from pickers, history kept) and deleted (only with no
  documents, or via privacy erasure — see 12-insights).
- **R6** A client page shows contact details, properties, and every request, quote, job, and
  invoice for that client with status, plus outstanding balance.

### Finding clients
- **R7** Searchable, paginated client list (name, email, phone, address), filterable by tag and
  archived state; sortable by name and recent activity.

### Import
- **R8** Import clients from a CSV with column mapping, preview, validation report, and
  duplicate handling. Large files process in the background with an emailed summary.

### Public request form
- **R9** Each business has a public, branded request page at a stable URL it can share or link
  from its website/social profiles.
- **R10** The form collects: name, contact info, service address, which services they're
  interested in (from the catalog, multi-select, optional), a description, preferred timing, and
  optional photos (count and size limited by plan).
- **R11** Submitting creates (or matches) a client and a request, shows a confirmation, emails
  the client an acknowledgment, and notifies the business.
- **R12** The form is protected against spam and abuse without hurting real users (no visible
  CAPTCHA by default).
- **R13** The business can turn the form off and customize its intro text.

### Request inbox
- **R14** Requests (from the form or entered by staff for phone/walk-in) appear in an inbox with
  status: New, In progress, Quoted, Archived.
- **R15** From a request, staff can create a quote pre-filled with the client, property,
  requested services and photos; the request links to resulting quotes.
- **R16** New request count is visible in navigation and on the dashboard.

### Client activity
- **R17** A per-client timeline of events (request received, quote sent/viewed/approved, visit
  completed, invoice paid, notes) gives anyone answering the phone full context.

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Clients are tenant-owned records, never users. | They never log in; avoids cross-tenant identity leakage. |
| D2 | Properties are first-class. | Property managers and landlords are a key persona (one client, many addresses). |
| D3 | No lead pipeline/stages, source tracking, or auto-assignment at launch. | A 3-status inbox covers 1–10 person businesses. |
| D4 | Client portal ("see all my stuff") is backlog. | Per-document client links cover the core loop. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [CLI-01](../specs/clients/CLI-01-client-records.md) | Client records & properties | M1 | ACC-04, PLT-06 |
| [CLI-02](../specs/clients/CLI-02-client-list-search.md) | Client list & search | M1 | CLI-01 |
| [CLI-03](../specs/clients/CLI-03-public-request-form.md) | Public request form | M2 | CLI-01, CAT-02, CAT-03, NTF-01 |
| [CLI-04](../specs/clients/CLI-04-request-inbox.md) | Request inbox | M2 | CLI-03, QTE-01 |
| [CLI-05](../specs/clients/CLI-05-client-timeline.md) | Client timeline | M4 | CLI-01, QTE-06, JOB-01, PAY-01 |
| [CLI-06](../specs/clients/CLI-06-client-import.md) | Client CSV import | M5 | CLI-01 |

## Backlog (M6)

- Embeddable request widget for the business's own website.
- Client hub: one link showing a client all their quotes, visits and invoices.
- Lead source tracking and simple conversion stats.
- Service-area filtering on the request form.
- Smart, industry-specific request questions (e.g. square footage, number of rooms).

## Open questions

1. Should the request form require an email, a phone, or either? Recommend either, with email
   strongly encouraged (needed for quote delivery without SMS).
2. Photo upload limits on Free plan (count/size) — owned by 09-billing.
3. Should duplicate detection ever auto-merge? Recommend never; suggest only.
4. Is "company" client (B2B) with multiple contacts needed at launch? Recommend one primary
   contact plus free-text additional contacts for now.
