---
id: INS-01
title: Action dashboard
domain: insights
milestone: M4
depends_on: [CLI-04, QTE-06, JOB-03, PAY-01]
---
# INS-01 · Action dashboard

> Requirements: [12-insights](../../plans/12-insights.md) R1–R4

## Summary

Replace the placeholder dashboard with a home screen that answers one question: "what needs me
right now?" — new requests, quotes waiting, work to schedule, today's visits, jobs to invoice and
money overdue — plus a tiny summary of how the month is going.

## User stories

- As an owner starting my day, I want one screen that tells me what to do next.
- As a brand-new owner, I want the dashboard to show me how to get started.

## Acceptance criteria

- [ ] Owners/Admins land on a dashboard with action groups, each showing a count and the top few
      items linking to the record: new requests; quotes with changes requested; quotes awaiting
      response (oldest first); approved but unscheduled jobs; today's visits (by member);
      completed jobs not invoiced; overdue invoices (oldest first).
- [ ] Empty groups collapse; when everything is empty, guidance points to the next step
      (onboarding checklist from ACC-05 while incomplete).
- [ ] A summary strip shows, for the current month: quotes sent (with plan usage once BIL-02
      exists), quote approval rate, and payments received.
- [ ] Technicians land on their day view (JOB-04) instead.
- [ ] The dashboard loads quickly for a busy business (measured with seeded data) and works on
      mobile as a stacked list.
- [ ] Tests cover each group's inclusion rules, role routing and tenancy.

## Out of scope

- Charts and reports (backlog). Customizable widgets (not planned).

## Open questions

- "Quotes awaiting response" — include only quotes older than N days to reduce noise?
  Recommend all, sorted oldest first, with age shown.
