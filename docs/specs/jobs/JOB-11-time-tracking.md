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

Hourly work is billed on what was actually spent, and owners need hours for payroll. Let team
members time their work on a visit or on general work (shop, travel), with rounding the business
chooses. On an hourly quote line, a visit's tracked hours become what was done (JOB-09) and are
billed at the line's rate (PAY-06). General time never reaches the client.

## User stories

- As a technician, I want to tap Start when I begin pruning and Stop when I'm done.
- As an owner, I want 3h41m billed as 3.75 hours at $80, and my crew's week of hours for payroll.

## Acceptance criteria

- [ ] On a scheduled visit, each assigned member can start and stop their own timer (question 9
      for visit Start/Complete), and several can run on one visit or job. Members can also clock
      in and out of general work not tied to a visit: shop, travel, training or other.
- [ ] Each entry keeps who, when it started and stopped, the visit and job or the general kind,
      and its rounded length. Rounding is a business setting (1, 5, 6, 10, 15 or 30 minutes,
      default 15); each entry rounds to the nearest interval (3h41m → 3.75 h).
- [ ] Members add and edit their own entries until the work is invoiced; office staff add and edit
      anyone's. Every change keeps who, when and the previous value, shown on the entry.
- [ ] On an hourly quote line (unit "hour"), each technician's rounded hours on a visit are their
      done quantity in JOB-09's log for that visit, fractions allowed (estimated 5, tracked 3.75,
      billed 3.75 × the rate). Editing an entry before invoicing updates it, with history: this
      is the one exception to JOB-09's "entries can't change once completed". The line with the
      time is question 1.
- [ ] Over the estimate, a business setting decides: **Cap at estimate** (the done quantity stops
      at the estimate and the extra hours become a QTE-10 change order for the client) or **Bill
      actual hours** (the extra hours bill at the line's rate as a line of their own on the job,
      so JOB-09's claim check still holds).
- [ ] Entries on invoiced work are locked: once a final bill (PAY-06) covers the hourly line, its
      entries can't change, for anyone; voiding the invoice unlocks them.
- [ ] General work time never bills a client. My day shows today's running timer and total; the
      job page shows hours per person and visit; technicians see hours, not money (JOB-04).
- [ ] Office access sees and edits everyone's time; a member sees only their own. Another
      business's entries are not found (tested). Timers and the entry form work at 360 px.
- [ ] Tests: start and stop, several timers on a visit, manual entries, each rounding interval
      and its edges, both over-estimate settings, edits and their history, own-versus-office
      rights, the invoice lock and a void, general work never billed, roles, tenancy.

## Out of scope

- Payroll integrations and pay rates; materials used per visit (backlog). GPS or geofencing.

## Decisions

- Team members clock in and out, and start or stop their own timers, on a scheduled visit or on
  general work not tied to a visit; several technicians can track time on one visit or job
  (owner, 2026-11-22).
- Techs add and edit their own entries until the work is invoiced; office staff add and edit
  anyone's; every change is logged with who, when and the previous value (owner, 2026-11-22).
- Rounding is a business setting (1, 5, 6, 10, 15 or 30 minutes, default 15), each entry to the
  nearest interval (owner, 2026-11-22).
- On an hourly line, a visit's rounded tracked hours are the done quantity in JOB-09's log;
  fractions are allowed (owner, 2026-11-22).
- Over the estimate, a business setting: cap at estimate (extra as a QTE-10 change order) or bill
  actual hours (owner, 2026-11-22). General work time never bills the client (owner, 2026-11-22).

## Implementation notes

- `time_entries` (user, visit and job or general kind, started, stopped, rounded minutes, source:
  timer or typed) and `time_entry_changes` (who, when, previous values). A visit's hourly entries
  feed JOB-09's `work_entries` (source: time), so billing reads one ledger; quantities are already
  decimal(12,4). Entries change under the job's row lock, and the invoice lock is PAY-06's.

## Open questions

1. A job with several hourly lines: where does time go? Recommend the timer asks once per visit
   (default: the first hourly line with hours left), changeable on the entry.
2. A timer never stopped? Recommend a reminder at the end of business hours, and an auto-stop at
   12 hours marked "Check this time" for the member and the office.
3. Overlapping entries? Recommend one running timer per person (starting one stops the other);
   overlapping typed entries are allowed with a warning, as visit conflicts are (06-jobs D3).
4. Started offline on a phone? Recommend keeping the phone's start time when it reconnects (up to
   24 hours back), marked "recorded offline".
5. Time zones? Recommend UTC stored, shown in the visit's location zone (CAT-07), general work in
   the business's (PLT-08).
6. Does the client see hours worked? Recommend yes as the hourly line's quantity on the invoice,
   with no per-person times.
7. Reports? Recommend a "Time entries" CSV in the export (INS-02) and a weekly hours-per-person
   page for payroll; payroll integrations later.
8. Where are the settings, and who changes them? Recommend Settings → Jobs, Owners and Admins (and
   ACC-07 roles that manage settings); changes apply to entries saved afterwards.
9. Does starting a visit (JOB-04) start the timer? Recommend Start offers to start yours (ticked),
   Complete stops it; teammates start their own.
