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

Today an approved quote becomes one job with all its lines. Real work splits: gutters this
week, 6 of 10 trees next month. Approval makes every line "to do" for its full quantity; staff
make jobs from whatever is ready. Completing a job is final, cancelling one gives its quantities
back. Billing is PAY-06 and PAY-08, the client's view QTE-09, changes to the quote QTE-10.

## User stories

- As an owner, I want 6 of a quote's 10 trees done now and the rest in spring, without a new quote.
- As an owner, I want a cancelled job's work back as "to do", ready for another job.

## Acceptance criteria

- [ ] **Create job** on an approved quote opens a picker of its lines with what's to do ("4 of
      10 to do"), each ticked at its full remaining quantity, which can be lowered. Ticked lines
      are copied with that quantity, the client, property, notes and files (JOB-01). A job needs
      one line above zero. With nothing to do there's no Create job.
- [ ] More jobs take what's left the same way. Asking for more than is left is refused, naming
      the jobs that hold it. A resubmitted picker (a double click) opens the job it already made.
- [ ] The automatic job on approval (JOB-01) and NTF-04's "Create job" take everything to do;
      with nothing left they're skipped and say why. Recurring quotes are JOB-10's.
- [ ] A line's fixed discount is shared by quantity across its jobs, the last claim taking the
      cent left over. A job from a quote carries no fixed quote discount: PAY-08 shares it on
      invoices. A percent discount is copied as now.
- [ ] Completing a job asks what was done per quote line (starting at what was booked); the job's
      quantity becomes that, and a shortfall isn't freed or rebooked. More done than booked claims
      the line's free quantity; past the quote's, question 1. A completed job's lines can't change.
- [ ] Raising a quote line's quantity on an open job claims free quantity; past the quote's it
      needs a change order (QTE-10). Lowering it, or removing the line, frees the difference.
      Lines added on the job are its own.
- [ ] Cancelling a job before it's completed frees its quantities. Reopening a cancelled job is
      refused while what it held isn't free; reopening a completed job is refused while an
      invoice that isn't void bills it, and otherwise claims back what it was booked for. Both
      the quote page's Create job and the job page's Reopen stay.
- [ ] A quote line's live claims never exceed its quantity, enforced by the database, so two
      people creating jobs at once can't both take the same trees (Implementation notes).
- [ ] Job pages say "From Q-0004: 2 of 3 services" and link the quote's other jobs; the quote
      page lists each line's jobs, quantities and statuses, and links "Jobs (2)".
- [ ] Every use of a quote's single job is changed (list in #356); billing's uses are PAY-06's.
- [ ] Existing data and the export follow the Implementation notes, behind a PLT-11 flag.
- [ ] Office access only (Owner, Admin, ACC-07 roles); technicians see their visit's job lines
      (JOB-04); a test shows QTE-07/08 quote-only members see no job. Another business's quote
      lines are not found. The picker and completion quantities work at 360 px.
- [ ] Tests: splits, repeated jobs, the race, a resubmitted picker, shortfalls and overruns,
      raising and lowering, cancel, both reopens, discount shares, automatic jobs, the migration
      both ways and its reconcile check, export, roles, tenancy.

## Decisions

- Quote = statement of work, approved once; job = a work item taking whole lines or part of a
  line's quantity, over one or more visits (owner, 2026-11-22).
- Completing is final: the quantity becomes what was done, and a shortfall isn't freed. The rest
  is finished by a change order (QTE-10) or a new quote for it (owner, 2026-11-22).
- Cancelling before completion frees its lines and quantities to "to do" (owner, 2026-11-22).
- Job title: the quote's when the job takes everything, else its lines ("Gutter clean, Windows";
  "Tree removal (6 of 10)"), editable. To-do quantity can be added to an open job ("Add from
  Q-0004"). A completed job reopens only while no invoice that isn't void bills it
  (owner, 2026-11-22).
- INS-01 gets a "Work not booked" group (approved quotes with to-do work, oldest first); to-do
  work never expires. Archiving keeps line states and leaves that group (owner, 2026-11-22).

## Implementation notes

- Claims are rows: `job_claims` (job, quote line, optional job line, quantity), and each job line
  keeps `quote_line_item_id` (on delete set null: quote lines go only on drafts; jobs are
  cancelled, not deleted). `quote_line_items.claimed_quantity` is the sum of live claims, kept by
  one atomic update with a check (claimed + not going ahead, QTE-09, ≤ quantity). The update takes
  the row lock, so concurrent claims queue and the loser fails the check; a sum across rows can't
  be a constraint. Lock order: quote, then job, then quote lines by id. A failed check rolls back
  to a savepoint and reports the lines. The picker carries a one-time token.
- Migration: each job that isn't cancelled claims its quote's lines, clamped to their quantities.
  Job lines match quote lines in position order on catalog item, name and unit price; a quote line
  with no match is claimed by that job without a job line. No total changes. A reconcile test
  checks claimed = the sum of live claims. Down raises once a quote has more than one job.
- Claims are kept whether the flag is on or off; the flag can't be turned on before PAY-06 ships.
- Export (new columns at the end): job lines get their quote line and claim; quote lines what's
  claimed, done and not going ahead.

## Open questions

1. More done than the quote's quantity at completion? Recommend completing with the quoted
   quantity and offering a change order (QTE-10) for the extra, which bills once approved.
