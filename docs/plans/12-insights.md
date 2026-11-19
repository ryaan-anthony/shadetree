# 12 · Insights & data

## Purpose

Show an owner what needs their attention right now, let them take all of their data with them
at any time, and (later) show whether the business is growing.

## Current state

A placeholder admin dashboard. The original plan had metrics dashboards, activity feeds, a
notifications center, audit logs, automated backups to customer storage, and six export
features.

## Requirements

### Action dashboard
- **R1** The home screen after sign-in is a short list of what needs attention:
  new requests, quotes awaiting response (and changes requested), approved quotes not yet
  scheduled, today's visits, completed jobs not invoiced, overdue invoices.
- **R2** Each item links to the record; counts show at a glance; empty states teach the next
  step for new businesses (e.g. "Send your first quote").
- **R3** A small summary strip: quotes sent this month (and plan usage), approval rate this
  month, payments received this month.
- **R4** Technicians land on their day view (06-jobs) instead.

### Data export
- **R5** Owners and Admins can export clients, properties, quotes (with line items), jobs and
  visits, invoices and payments as CSV, and a full-account export (all CSVs + documents' PDFs and
  uploaded files) as a single download.
- **R6** Large exports are produced in the background; the requester is emailed a link that
  expires. Export requests are logged.
- **R7** Exports are available on every plan, including Free.

### Privacy requests
- **R8** A business can erase a client's personal data on request (anonymize the client while
  keeping financial records' totals intact), with confirmation.

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | "What needs attention" beats charts for the home screen. | Owners act on lists; charts are rarely revisited. |
| D2 | Exports on every plan. | Data portability is a trust promise and reduces sign-up fear. |
| D3 | No automated backups to customer storage. | Exports + our own backups cover the need. |
| D4 | Business-level audit log is backlog; operator actions are audited from launch (OPS-01). | Small teams rarely need it; operator audit is a security requirement. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [INS-01](../specs/insights/INS-01-action-dashboard.md) | Action dashboard | M4 | CLI-04, QTE-06, JOB-03, PAY-01 |
| [INS-02](../specs/insights/INS-02-data-export.md) | Data export & client erasure | M5 | CLI-01, QTE-06, JOB-01, PAY-05 |

## Backlog (M6)

- Reports: revenue by month, quote win rate, revenue by service, average time to approval/payment.
- Business activity/audit log (who changed what).
- Scheduled exports; accounting integrations.

## Open questions

1. Should the dashboard's summary strip be visible to Admins or only Owners? Recommend both.
2. Retention of export files — recommend 7 days.
3. Erasure vs. legal record-keeping for invoices — confirm with legal review (MKT-03). INS-02
   keeps documents and totals under "Erased client" and removes the person's details.
