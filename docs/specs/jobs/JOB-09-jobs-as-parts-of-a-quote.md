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

- [x] **Create job** on an approved quote (except recurring ones, JOB-10) opens a picker of what's
      to do ("4 of 10 to do"), each line ticked at its remaining quantity, which can be lowered;
      ticked lines are copied with the client, property, notes and files (JOB-01).
- [x] More jobs take what's left; asking for more is refused, naming the jobs that hold it. A
      resubmitted picker opens the job it made. The automatic job on approval and NTF-04's
      "Create job" take everything to do, or are skipped saying why; not on recurring quotes.
- [x] Jobs from a quote carry no fixed discounts, line or quote: PAY-08 shares them on invoices.
      A percent discount is copied as now.
- [x] Anyone assigned to one of the job's visits logs the work from that visit (My day, JOB-04):
      quantities done per line (hourly lines from tracked time and its overrun setting, JOB-11),
      lines added on site (priced as Decisions say), notes and photos. Each entry keeps who,
      which visit and when; the job page shows them per line ("Marcus 4, Riley 2").
      *Hourly lines take tracked time once JOB-11 ships; until then hours are logged as typed.*
- [x] Completing the job stays with office access; a visit, with its assignees. Completion starts
      at the logged totals (else what was booked); the job's quantity becomes what's confirmed,
      and a shortfall isn't freed. More done than booked claims free quantity; more than the
      quote's starts QTE-10's overrun change order. Once completed, its lines and entries can't
      change, except tracked time before invoicing (JOB-11) and an approved overrun (QTE-10).
      *Until QTE-10 ships, confirming more than the quote has is refused (Decisions).*
- [x] Raising a quote line on an open job claims free quantity; past the quote's it needs a change
      order. Lowering or removing it frees the difference. Lines added on site are the job's own.
- [x] Cancelling an open job frees its quantities. Reopening a cancelled job is refused while what
      it held isn't free. Reopening a completed job is refused while an invoice that isn't void
      bills it; otherwise its lines return to their booked quantities (the claim never changed).
      The quote's Create job and the job's Reopen both stay.
- [x] A quote line's live claims never exceed its quantity, enforced by the database: two people
      can't both take the same trees.
- [x] Job pages say "From Q-0004: 2 of 3 services"; the quote page lists each line's jobs and
      statuses ("Jobs (2)"). Every use of a quote's single job changes (list in #356).
- [x] Making, completing, cancelling and reopening jobs stay with office access; QTE-07/08 members
      see no job; another business's lines aren't found (tested). Works at 360 px.
- [x] Tests: splits, the race, a resubmitted picker, two people logging, shortfalls, overruns,
      raise, lower, cancel, reopens, automatic jobs, migration, reconcile, export, roles, tenancy.

## Decisions

- Quote = statement of work, approved once; job = a work item taking whole lines or part of a
  line's quantity, over one or more visits (owner, 2026-11-22).
- Completing is final: the quantity becomes what was done, and a shortfall isn't freed. The rest
  is finished by a change order (QTE-10) or a new quote for it (owner, 2026-11-22).
- Cancelling before completion frees its lines and quantities to "to do" (owner, 2026-11-22).
- Job title: the quote's when the job takes everything, else its lines ("Tree removal (6 of
  10)"), editable. To-do work can be added to an open job. A completed job reopens only while no
  invoice that isn't void bills it (owner, 2026-11-22).
- INS-01 gets a "Work not booked" group; to-do work never expires; archiving keeps line states
  (owner, 2026-11-22).
- Overrun work already done is offered by a change order, added to the job once approved
  (QTE-10) (owner, 2026-11-22).
- Several technicians can be assigned to a job, and each can log the work. Each corrects only
  their own entries; the office corrects anyone's (owner, 2026-11-22).
- A line added on site is a catalog service at its price, or an unpriced custom line the office
  prices before invoicing (owner, 2026-11-22).
- The ledger over `lock_version` (coordinator; follows the owner's model).
- Unpriced on-site lines: the Complete dialog asks a price for each ($0 typed on purpose);
  saving the job form as is doesn't price them (owner, 2026-11-23).
- More done than the quote has: refused at completion, interim until QTE-10 (owner, 2026-11-23).
- Removing a job line keeps its work log (owner, 2026-11-23). The quote page's Create invoice is
  the Primary only while completed work is unbilled (owner, 2026-11-23).

## Implementation notes

- Behind `split_jobs` (PLT-11; on after PAY-06 and PAY-08). Off: one job per quote, its lines in
  full, claiming what's free. `job_claims` (job, or invoice line for direct billing): live while the
  job isn't cancelled or the invoice void. Check: `claimed_quantity >= 0 AND claimed_quantity <=
  quantity`, kept by `QuoteWork`. Lock order: quote, jobs by id, lines by id, then visits.
- `jobs.picker_token` (a cancelled job's token asks again); `Quote#first_job` replaces `has_one :job`.
  Completion keeps `booked_quantity` and the claim's `extra_quantity` for a reopen.
- `work_entries` is append-only and keeps `item_name` (the line's key nullifies). Migration: jobs'
  and directly billed invoices' claims, matched and clamped; down refuses two jobs. Export:
  flagged columns, `job_claims`, `work_log`. "Work not booked" links to Approved until QTE-09.
- Later specs: JOB-11 writes source "time" (log_work! diffs typed entries only) and needs a path
  after completion; PAY-08 counts pre-JOB-09 jobs' fixed discounts; JOB-10 excludes recurring
  quotes from `from_quote!`, the automatic job and the picker; PAY-06 takes over direct claims
  (`QuoteWork.claim_direct!`/`release_direct!`) and frees one before deleting its invoice line.
- Dev seeds: "Backyard trees and gutters" (6 of 10 trees, logged work, an unpriced stump).
