---
id: JOB-09
title: Jobs as parts of a quote
domain: jobs
milestone: M6
depends_on: [JOB-01, PLT-11, PLT-14]
---
# JOB-09 · Jobs as parts of a quote

> Requirements: [06-jobs](../../plans/06-jobs.md) R1, R17

## Summary

An approved quote's work splits: gutters this week, 6 of 10 trees next month. Staff make jobs
from whatever is "to do", the crew log what they did, completing is final and cancelling gives the
work back. Billing: PAY-06, PAY-08; the client's view: QTE-09; changes: QTE-10; time: JOB-11.

## User stories

- As an owner, I want 6 of a quote's 10 trees done now and the rest in spring, without a new quote.
- As a technician, I want to log my 4 trees while Riley logs his 2, without either of us losing it.

## Acceptance criteria

- [ ] **Create job** on an approved quote opens a picker of what's to do ("4 of 10 to do"), each
      line ticked at its remaining quantity, which can be lowered; ticked lines are copied with the
      client, property, notes and files (JOB-01). A job needs one line above zero.
- [ ] More jobs take what's left; asking for more is refused, naming the jobs that hold it. A
      resubmitted picker opens the job it made. The automatic job on approval (JOB-01) and NTF-04's
      "Create job" take everything to do, or are skipped saying why. Recurring quotes: JOB-10.
- [ ] A line's fixed discount is shared by quantity across its jobs, the last claim taking the left
      over cent. Jobs carry no fixed quote discount (PAY-08 shares it); a percent one is copied.
- [ ] Anyone assigned to one of the job's visits logs the work from that visit (My day, JOB-04):
      quantities done per line (hourly lines from tracked time, JOB-11), lines added on site
      (question 2), notes and photos. Each entry
      keeps who, which visit and when; the job page shows them per line ("Marcus 4, Riley 2").
      Two people logging at once never overwrite each other (Implementation notes).
- [ ] Completing the job stays with office access and a visit with its assignees, as now. It
      starts at the logged totals (else what was booked); the job's quantity becomes what's
      confirmed, and a shortfall isn't freed. More done than booked claims free quantity; past
      the quote's, see Decisions. Once completed, its lines and entries can't change (tracked time
      until invoiced: JOB-11).
- [ ] Raising a quote line on an open job claims free quantity; past the quote's it needs a change
      order (QTE-10). Lowering or removing it frees the difference. Lines added on site are its own.
- [ ] Cancelling an open job frees its quantities. Reopening a cancelled job is refused while what
      it held isn't free; a completed one, while an invoice that isn't void bills it (otherwise it
      claims back what it was booked for). The quote's Create job and the job's Reopen both stay.
- [ ] A quote line's live claims never exceed its quantity, enforced by the database: two people
      can't both take the same trees.
- [ ] Job pages say "From Q-0004: 2 of 3 services"; the quote page lists each line's jobs and
      statuses ("Jobs (2)"). Every use of a quote's single job changes (list in #356).
- [ ] Making, completing, cancelling and reopening jobs stay with office access; QTE-07/08 members
      see no job; another business's lines aren't found (tested). Works at 360 px.
- [ ] Tests: splits, the race, a resubmitted picker, two people logging, shortfalls, overruns,
      raise, lower, cancel, reopens, discounts, automatic jobs, migration, export, roles, tenancy.

## Decisions

- Quote = statement of work, approved once; job = a work item taking whole lines or part of a
  line's quantity, over one or more visits (owner, 2026-11-22).
- Completing is final: the quantity becomes what was done, and a shortfall isn't freed. The rest
  is finished by a change order (QTE-10) or a new quote for it (owner, 2026-11-22).
- Cancelling before completion frees its lines and quantities to "to do" (owner, 2026-11-22).
- Job title: the quote's when the job takes everything, else its lines ("Tree removal (6 of
  10)"), editable. To-do work can be added to an open job ("Add from Q-0004"). A completed job
  reopens only while no invoice that isn't void bills it (owner, 2026-11-22).
- INS-01 gets a "Work not booked" group (approved quotes with to-do work, oldest first); to-do
  work never expires. Archiving keeps line states and leaves that group (owner, 2026-11-22).
- More done than the quote's quantity: the job completes with the quoted quantity, and a change
  order (QTE-10) for the extra bills once approved (owner, 2026-11-22).
- Several technicians can be assigned to a job, and each can log the work (owner, 2026-11-22).

## Implementation notes

- Claims are rows: `job_claims` (job, quote line, optional job line, quantity); job lines keep
  `quote_line_item_id` (on delete set null: quote lines go only on drafts; jobs are cancelled,
  not deleted). `quote_line_items.claimed_quantity` (sum of live claims) changes by one atomic
  update with a check against the quantity (plus QTE-09's not going ahead); its row lock queues
  rivals and the loser fails the check. Lock order: quote, job, quote lines by id; a failed check
  rolls back to a savepoint. The picker carries a one-time token.
- Logging is a ledger: `work_entries` (job line, visit, user, quantity, time), append-only; a
  correction is another entry, and a line's done quantity is their sum. Chosen over `lock_version`
  because phones on patchy signal would hit stale-version retries, while appends never conflict
  and are the history. An entry takes the job's row lock and checks it's open; completion takes
  the quote's, then the job's, then sums and runs the claim check, so nothing lands after it.
- Migration: each live job claims its quote's lines, clamped to their quantities, matching job
  lines in position order on catalog item, name and unit price (unmatched: a claim with no job
  line). No total changes; a reconcile test checks claimed = Σ live claims; down raises once a
  quote has two jobs.
- Claims are kept with the PLT-11 flag on or off; it can't be turned on before PAY-06 ships.
- Export (new columns at the end): job lines get their quote line and claim, quote lines what's
  claimed, done and not going ahead; a work log table has one row per entry.

## Open questions

1. Can one technician correct another's entry? Recommend no, matching JOB-11's time rule: each
   corrects their own (quantities while the job is open, as a new entry); the office, anyone's.
2. Lines a technician adds on site: priced how? Recommend a catalog service at its price, or an
   unpriced custom line the office prices before invoicing; price visibility stays as JOB-04.
