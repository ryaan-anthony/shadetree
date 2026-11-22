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
make jobs from whatever is ready, whole lines or part of a line's quantity. Completing a job is
final, and cancelling one gives its quantities back. Billing is PAY-06, the client's view QTE-09.

## User stories

- As an owner, I want 6 of a quote's 10 trees done now and the rest in spring, without a new quote.
- As an owner, I want a cancelled job's work back as "to do", ready for another job.

## Acceptance criteria

- [ ] **Create job** on an approved quote opens a picker of its lines with what's still to do
      ("4 of 10 to do"), each ticked at its full remaining quantity, which can be lowered. Ticked
      lines are copied with that quantity, the client, property, notes and files (JOB-01). A job
      needs one line with a quantity above zero. With nothing to do there's no Create job.
- [ ] More jobs take what's still to do the same way. Asking for more than is left is refused,
      naming the jobs that hold it; if one job took everything asked for a moment ago (a double
      click), you're sent to that job.
- [ ] The automatic job on approval (JOB-01) and NTF-04's "Create job" take everything still to
      do; with nothing left they're skipped and say why.
- [ ] Completing a job asks what was done per quote line (starting at what was booked). The
      job's quantity becomes that; a shortfall isn't freed or rebooked. A completed job's lines
      can't change (owner: done means done; reopening is question 3).
- [ ] Cancelling a job before it's completed frees its quantities back to "to do". Removing a
      quote line from the job form, or lowering its quantity, frees the difference; lines added on
      the job are its own. Reopening a cancelled job is refused while what it held isn't free.
- [ ] Across a quote line's jobs that aren't cancelled, the claimed quantity never exceeds the
      line's, enforced by the database (Implementation notes), so two people creating jobs at once
      can't both take the same trees.
- [ ] Job title: question 1. The job page says "From Q-0004: 2 of 3 services" and links the
      quote's other jobs; the quote page lists each line's jobs with quantity and status.
- [ ] Every use of a quote's single job is changed: the quote's one job and its unique index,
      Create job (and its double-click return), the automatic and NTF-04 jobs, the quote page's
      job link ("Jobs (2)" when several), and the export. Billing's uses are PAY-06's.
- [ ] Existing data: each job that isn't cancelled claims its quote's lines, matched or not. Job
      lines are matched to quote lines in position order on catalog item, name and unit price;
      unmatched ones are the job's own. No total changes. Undoing the migration is refused once a
      quote has more than one job. The new behaviour is behind a PLT-11 flag until launch.
- [ ] Data export (INS-02), new columns at the end: job lines get the quote line they came from
      and the quantity claimed; quote lines what's claimed and done.
- [ ] Jobs stay with office access (Owner, Admin, ACC-07 roles); technicians see only their
      visit's job lines (JOB-04). A test shows QTE-07/08 quote-only members see no job.
      Pickers take only that quote's lines; another business's are not found.
- [ ] The picker and the completion quantities work at 360 px.
- [ ] Tests: split and repeated jobs, the race and double click, completion with a shortfall,
      cancel, remove, lower, reopen, automatic jobs, migration both ways, export, roles, tenancy.

## Out of scope

- Billing (PAY-06), the client page and "Not going ahead" (QTE-09), deposits (PAY-07), recurring
  jobs (JOB-10). Jobs without a quote don't change.

## Decisions

- Quote = statement of work, approved once; job = a work item taking whole lines or part of a
  line's quantity, over one or more visits (owner, 2026-11-22).
- Completing a job is final: its quantity becomes what was done, and a shortfall isn't freed or
  rebooked; finishing it needs a new quote or a revision (owner, 2026-11-22).
- Cancelling before completion frees its lines and quantities to "to do" (owner, 2026-11-22).

## Implementation notes

- `job_line_items.quote_line_item_id` (on delete set null: quote lines go only on drafts, jobs
  are cancelled, never deleted) and `.claimed_quantity` (its `quantity` becomes what was done).
- Over-claiming is stopped by `quote_line_items.claimed_quantity`, changed by one atomic
  update with a check that it stays within the line's quantity (QTE-09 adds "Not going ahead" to
  the check). The update takes the line's row lock, so concurrent claims queue and the loser
  fails the check; a sum across job rows can't be a constraint. Reopening a cancelled job adds
  its claim back the same way and is refused, with the reason, if the check fails.

## Open questions

1. Job title? Recommend the quote's title when the job takes everything, else its lines ("Gutter
   clean, Windows"; "Tree removal (6 of 10)"); editable as now.
2. Adding to-do quantity to an existing job from its form? Recommend yes ("Add from Q-0004"),
   open jobs only, under the same check.
3. Can a completed job be reopened? Recommend only while no invoice that isn't void bills it,
   for mistakes; its claim never left, so nothing conflicts.
4. A shortfall "needs a new quote or a revision", but approved quotes can't be revised (QTE-06).
   Recommend "Quote the rest": a new draft for the client with the shortfall's lines.
5. A "Work not booked" group on the dashboard (INS-01)? Recommend yes: approved quotes with
   to-do work, oldest first. To-do work never expires; staff mark it "Not going ahead" (QTE-09).
6. Archived approved quotes? Recommend archiving keeps line states; it leaves "Work not booked"
   and Create job stays possible after restoring.
