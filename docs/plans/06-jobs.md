# 06 · Jobs & scheduling

## Purpose

Turn approved work into scheduled visits, make sure the right person shows up at the right
place, and let technicians record that the work is done — from their phone.

## Current state

Nothing implemented. Unused tables exist for staff weekly availability and business hours per
location. The original plan focused on client self-scheduling, calendar sync, and route
optimization before basic scheduling existed.

## Requirements

### Jobs
- **R1** A job is created from an approved quote (copying client, property, line items) or
  directly (for work agreed by phone). A job belongs to one client and one property.
- **R2** Job statuses: Unscheduled → Scheduled → In progress → Completed, or Cancelled. Status is
  mostly derived from its visits.
- **R3** Job page shows client & property, line items, notes, attachments/photos, visits, and
  links to the originating quote and resulting invoice(s).
- **R4** Completing a job prompts creating an invoice (07-payments).

### Visits
- **R5** A job has one or more visits. A visit has a date, either a start time or an arrival
  window (e.g. 9–11am) or "anytime", an estimated duration, and assigned members (zero or more).
- **R6** Visits can be rescheduled, reassigned, and cancelled. Changes are recorded.
- **R7** Visits warn (not block) when they fall outside business hours, on a closure, or overlap
  another visit for the same member.

### Calendar
- **R8** Staff calendar with day and week views, filterable by member; an "unscheduled" list of
  jobs needing a visit. Works on phones (agenda-style list) and desktops (grid).
- **R9** Rescheduling from the calendar is fast (drag on desktop; quick edit on mobile).

### Technician day
- **R10** A technician sees "My day": today's (and upcoming) visits in order, each with client
  name, property address (tap to open maps), access notes, tap-to-call/text, job line items and
  notes.
- **R11** From a visit, a technician can mark start and complete, add notes, and attach photos
  (count/size limited). Completion time is recorded.
- **R12** Technicians cannot see prices or invoices unless the business allows it (setting).
- **R15** Request follow-ups (site visits and calls, 04-clients R18) sit on My day and the staff
  calendar next to job visits, and are moved and reassigned the same ways.

### Client communication
- **R13** The client receives a confirmation when a visit is scheduled or changed or cancelled,
  with a client link showing date/window, address and business contact; and a reminder the day
  before (email).
- **R14** Business can turn each of these messages off.

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Staff-driven scheduling first; client self-booking is backlog. | Original MVP list already deferred self-booking; it needs availability modeling. |
| D2 | Arrival windows are first-class. | How most home-service businesses actually schedule. |
| D3 | Conflicts warn, don't block. | Small teams double-book deliberately; blocking frustrates. |
| D4 | No per-member weekly availability at launch. | Only needed for self-booking; business hours suffice for warnings. |
| D5 | No two-way calendar sync; a read-only calendar feed is backlog. | Two-way sync is a support burden. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [JOB-01](../specs/jobs/JOB-01-jobs.md) | Jobs | M3 | QTE-05, CLI-01 |
| [JOB-02](../specs/jobs/JOB-02-visits.md) | Schedule visits | M3 | JOB-01, ACC-04, CAT-06 |
| [JOB-03](../specs/jobs/JOB-03-calendar.md) | Staff calendar | M3 | JOB-02 |
| [JOB-04](../specs/jobs/JOB-04-technician-day.md) | Technician day view | M3 | JOB-02 |
| [JOB-05](../specs/jobs/JOB-05-visit-notifications.md) | Visit confirmations & reminders | M3 | JOB-02, NTF-01, PLT-12 |
| [JOB-06](../specs/jobs/JOB-06-requests-on-my-day.md) | Request follow-ups on My day | M6 | CLI-07, JOB-04 |
| [JOB-07](../specs/jobs/JOB-07-requests-on-calendar.md) | Request follow-ups on the calendar | M6 | CLI-07, JOB-03 |

## Backlog (M6)

- Client self-scheduling after approval (needs member availability and time off).
- Recurring jobs (weekly mowing, monthly pest control) — high retention value; first M6 candidate.
- Read-only calendar feed (ICS) per member.
- "On my way" message to client.
- Time tracking / materials used per visit.
- Route ordering for a day's visits.
- Checklists per service.

## Open questions

1. Should jobs without a quote be allowed on the Free plan? Recommend yes — usage is metered on
   quotes, and blocking jobs would push users away.
2. Do completed visits capture a client signature on-site? Recommend backlog.
3. Should visit reminders be on by default? Recommend yes for email.
4. Photos per visit: limit and retention per plan — owned by 09-billing and PLT-01 storage ADR.
