---
id: JOB-01
title: Jobs
domain: jobs
milestone: M3
depends_on: [QTE-05, CLI-01]
---
# JOB-01 · Jobs

> Requirements: [06-jobs](../../plans/06-jobs.md) R1–R4

## Summary

An approved quote becomes work the business has committed to do. A job captures what will be
done, for whom and where, and is the anchor for visits, technician notes and the eventual
invoice. Jobs can also be created directly for work agreed by phone.

## User stories

- As an owner, I want to turn an approved quote into a job in one tap so that nothing falls
  through the cracks between "yes" and "scheduled".
- As an admin, I want to create a job for a repeat client without sending a quote first.
- As an owner, I want one page that shows everything about a job.

## Acceptance criteria

- [x] Owners/Admins create a job from an approved quote (client, property, line items, notes and
      attachments copied; quote ↔ job linked) or from scratch (client, property, title, line
      items optional, instructions).
      *Line items can be changed, added and removed on the job form; the quote doesn't change.
      Job lines need a name and a quantity; a blank price is zero on every kind of line.*
- [x] Optionally, approving a quote can auto-create the job (business setting, default on;
      may later become an automation recipe, NTF-04). *Settings → Documents → Jobs. It runs after
      the approval is saved, so a failure never undoes the client's answer.*
- [x] Job statuses: Unscheduled, Scheduled, In progress, Completed, Cancelled — derived from
      visits where possible, with manual Complete/Cancel (with reason) available.
      *Derived from visits (JOB-02), with manual Complete, Cancel with a reason, and Reopen.*
- [ ] The job page shows client & property (with access notes), line items, instructions for
      the crew, internal notes, attachments/photos, visits (from JOB-02), and links to the
      originating quote and any invoices.
- [x] A job list filters by status (with an "approved but unscheduled" shortcut), searches by
      client/title/number, and is usable on mobile. *"Needs scheduling" is the shortcut.*
- [ ] Completing a job prompts "Create invoice" (wired up in PAY-01).
- [x] Jobs appear on the client page.
- [x] Technicians see a job only through visits assigned to them (JOB-04).
      *Through My day; the job and client pages stay Owner/Admin only.*
- [x] Tests cover creation paths, status derivation, roles and tenancy. *Derivation from visits is tested with JOB-02's visits.*

## Out of scope

- Visits and scheduling (JOB-02). Recurring jobs, checklists, time/materials (backlog).

## Open questions

- ~~Should editing job line items after creation be allowed?~~ *Decided: yes. The approved quote
  stays unchanged; the invoice uses the job's items.*
- ~~Job numbering: sequential per business like quotes?~~ *Decided: yes, J-0001, J-0002…*

## Implementation notes

- #289: the job filters read "Not finished" and "Ready to invoice".
- #289: when no job is left to do, the list says "Nothing to do" and offers "Show 1 completed
  job"; "Open" stays the default filter.
