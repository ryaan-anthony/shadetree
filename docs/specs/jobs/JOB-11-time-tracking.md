---
id: JOB-11
title: Time tracking
domain: jobs
milestone: M6
depends_on: [JOB-09, JOB-04, PAY-06, QTE-10]
---
# JOB-11 · Time tracking

> Requirements: [06-jobs](../../plans/06-jobs.md) R19

## Summary

Hourly work should be billed on what was actually spent. Let technicians time their client work
on a visit, with rounding the business chooses. On an hourly quote line, a visit's tracked hours
become what was done (JOB-09) and are billed at the line's rate (PAY-06). This is time on client
work only: timesheets and payroll are out of scope.

## User stories

- As a technician, I want to tap Start when I begin pruning and Stop when I'm done.
- As an owner, I want 3h41m of pruning billed as 3.75 hours at $80.

## Acceptance criteria

- [ ] On a scheduled visit, each assigned member can start and stop their own timer (visit Start
      and Complete: Decisions), and several can run on one visit or job. Time is only ever on a
      visit or the job it belongs to.
- [ ] Each entry keeps who, when it started and stopped, the visit and job, and its rounded
      length. Rounding is a business setting (1, 5, 6, 10, 15 or 30 minutes,
      default 15); each entry rounds to the nearest interval (3h41m → 3.75 h).
- [ ] Members add and edit their own entries until the work is invoiced; office staff add and edit
      anyone's. Every change keeps who, when and the previous value, shown on the entry.
- [ ] On an hourly quote line (unit "hour"), each technician's rounded hours on a visit are their
      done quantity in JOB-09's log for that visit, fractions allowed (estimated 5, tracked 3.75,
      billed 3.75 × the rate). Editing an entry before invoicing updates it, with history: this
      is the one exception to JOB-09's "entries can't change once completed". The line it goes to:
      Decisions.
- [ ] Over the estimate, a business setting decides: **Cap at estimate** (the done quantity stops
      at the estimate and the extra hours become a QTE-10 change order for the client) or **Bill
      actual hours** (the extra hours bill at the line's rate as a line of their own on the job,
      so JOB-09's claim check still holds).
- [ ] Entries on invoiced work are locked: once a final bill (PAY-06) covers the hourly line, its
      entries can't change, for anyone; voiding the invoice unlocks them.
- [ ] My day shows the running timer and the visit's tracked time; technicians see hours, not
      money (JOB-04). The job page shows the office hours per visit
      and person, with each entry's history.
- [ ] Office access sees and edits everyone's time; a member sees only their own. Another
      business's entries are not found (tested). Timers and the entry form work at 360 px.
- [ ] Tests: start and stop, several timers on a visit, manual entries, each rounding interval
      and its edges, both over-estimate settings, edits and their history, own-versus-office
      rights, the invoice lock and a void, roles, tenancy.

## Out of scope

- Employee timesheets and payroll: no time on general work (shop, travel and so on), no clocking
  in or out for a shift, no timesheet views, no payroll export (owner, 2026-11-22).
- Pay rates; materials used per visit (backlog); GPS or geofencing.

## Decisions

- Technicians start and stop their own timers on a scheduled visit; several can track time on
  one visit or job. Time is tracked only against client work: a visit, or its job
  (owner, 2026-11-22).
- Techs add and edit their own entries until the work is invoiced; office staff add and edit
  anyone's; every change is logged with who, when and the previous value (owner, 2026-11-22).
- Rounding is a business setting (1, 5, 6, 10, 15 or 30 minutes, default 15), each entry to the
  nearest interval (owner, 2026-11-22).
- On an hourly line, a visit's rounded tracked hours are the done quantity in JOB-09's log;
  fractions are allowed (owner, 2026-11-22).
- Over the estimate, a business setting: cap at estimate (extra as a QTE-10 change order) or bill
  actual hours (owner, 2026-11-22).
- Several hourly lines: the timer asks once per visit (default the first with hours left),
  changeable on the entry. One running timer per person; starting one stops the other;
  overlapping typed entries are allowed with a warning (owner, 2026-11-22).
- A timer left running gets a reminder at the end of business hours and stops at 12 hours,
  marked "Check this time". Started offline, it keeps the phone's start time (up to 24 hours
  back), marked "recorded offline". Stored in UTC, shown in the visit's location zone
  (owner, 2026-11-22).
- Clients see hours only as the hourly line's quantity on the invoice, with no per-person
  times. The office sees a job's time on the job page (owner, 2026-11-22).
- The settings are in Settings → Jobs, changed by Owners, Admins and ACC-07 roles that manage
  settings, for entries saved afterwards. Starting a visit offers to start your timer (ticked);
  completing it stops it; teammates start their own
  (owner, 2026-11-22).

## Implementation notes

- `time_entries` (user, job, visit, started, stopped, rounded minutes, source:
  timer or typed) and `time_entry_changes` (who, when, previous values). A visit's hourly entries
  feed JOB-09's `work_entries` (source: time), so billing reads one ledger; quantities are already
  decimal(12,4). Entries change under the job's row lock, and the invoice lock is PAY-06's.
