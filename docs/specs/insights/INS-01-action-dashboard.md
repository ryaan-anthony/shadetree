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

- [x] Owners/Admins land on a dashboard with action groups, each showing a count and the top few
      items linking to the record: new requests; quotes with changes requested; quotes awaiting
      response (oldest first); approved but unscheduled jobs; today's visits (by member);
      completed jobs not invoiced; overdue invoices (oldest first).
- [x] Empty groups collapse; when everything is empty, guidance points to the next step
      (onboarding checklist from ACC-05 while incomplete).
- [x] A summary strip shows, for the current month: quotes sent (with plan usage once BIL-02
      exists), quote approval rate, and payments received.
- [x] Technicians land on their day view (JOB-04) instead.
- [x] The dashboard loads quickly for a busy business (measured with seeded data) and works on
      mobile as a stacked list.
- [x] Tests cover each group's inclusion rules, role routing and tenancy.

## Out of scope

- Charts and reports (backlog). Customizable widgets (not planned).

## Decisions

- Quotes awaiting response: all of them, oldest first, with how long ago each was sent.

## Implementation notes

- `ActionDashboard` builds each group (a count and the top five, each linking to its record,
  with "See all" opening the matching list tab): new requests; quotes with changes asked for;
  quotes awaiting an answer (oldest sent first, archived ones left out); jobs with nothing
  booked; completed jobs with no invoice (a void one doesn't count); overdue invoices (oldest
  due first, with the balance and days late). Today's visits are grouped by the people on them,
  "Not assigned" last.
- Empty groups don't show; with nothing at all, "You're all caught up" with a New quote button.
  The setup checklist (ACC-05) stays above while it's showing.
- The month strip: quotes sent (the billable "quote_sent" usage events, which BIL-02's plan
  limits will count), the approval rate of quotes answered this month (approved ÷ approved or
  declined), and payments received (by date received, recorded and online).
- Speed: a fixed number of queries however busy the business is (a test checks that adding
  thirty records adds no queries beyond a small margin). On phones the groups stack, with
  today's visits last.
