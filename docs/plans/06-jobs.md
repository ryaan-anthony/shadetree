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
- **R17** An approved quote's lines, or parts of their quantities, can be shared among several
  jobs. Across a line's jobs that aren't cancelled, the quantity never exceeds the line's;
  completing a job is final (its quantity becomes what was done), and cancelling one frees its
  quantities. Billing is 07-payments R17; changing an approved quote is 05-quotes R23.
- **R18** A recurring quote, approved once, produces a job per occurrence from the same lines,
  each billed when completed.
- **R19** Team members track time on visits and general work, rounded as the business sets; on
  hourly lines, tracked hours are what's done and billed. General time never bills a client.

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
- **R16** People who schedule but can't see requests see others' follow-ups as anonymous "Busy"
  time, so they can plan around them without seeing the requests.

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
| [JOB-08](../specs/jobs/JOB-08-busy-blocks.md) | Busy blocks for schedulers without requests | M6 | JOB-07, ACC-07 |
| [JOB-09](../specs/jobs/JOB-09-jobs-as-parts-of-a-quote.md) | Jobs as parts of a quote | M6 | JOB-01, PLT-11, PLT-14 |
| [JOB-10](../specs/jobs/JOB-10-recurring-jobs.md) | Recurring jobs | M6 | JOB-09, PAY-06, JOB-02, QTE-09, QTE-01 |
| [JOB-11](../specs/jobs/JOB-11-time-tracking.md) | Time tracking | M6 | JOB-09, JOB-04, PAY-06, QTE-10 |

## Backlog (M6)

- Client self-scheduling after approval (needs member availability and time off).
- Recurring jobs (weekly mowing, monthly pest control): specified as JOB-10, the first M6 item.
- Read-only calendar feed (ICS) per member.
- "On my way" message to client.
- Materials used per visit (time tracking is JOB-11).
- Route ordering for a day's visits.
- Checklists per service.

## Open questions

1. Should jobs without a quote be allowed on the Free plan? Recommend yes — usage is metered on
   quotes, and blocking jobs would push users away.
2. Do completed visits capture a client signature on-site? Recommend backlog.
3. Should visit reminders be on by default? Recommend yes for email.
4. Photos per visit: limit and retention per plan — owned by 09-billing and PLT-01 storage ADR.
