---
id: JOB-09
title: Multiple jobs per quote
domain: jobs
milestone: M6
depends_on: [JOB-01, PAY-01, PLT-14]
---
# JOB-09 · Multiple jobs per quote

> Requirements: [06-jobs](../../plans/06-jobs.md) R1, R17; [07-payments](../../plans/07-payments.md) R1

## Summary

Today an approved quote becomes one job with all its lines. Real work splits: gutters this
week, windows next month, the shed never. Share a quote's lines (services) among several jobs,
each line in at most one job that isn't cancelled, and done once. Invoicing the quote bills the
lines whose jobs are completed, and the client's quote page shows where each service stands.

## User stories

- As an owner, I want two of three services done now, the third in spring, and a cancelled
  job's services back for a new job without a new quote.
- As a client, I want to see which services are booked, done and billed, and for how much.

## Acceptance criteria

- [ ] **Create job** on an approved quote asks which of its free lines the job is for (all ticked;
      a line is free when it's in no job, or only in cancelled ones) and copies those, with the
      client, property, notes and files, as JOB-01 does. A job needs at least one line.
      Later jobs take the lines still free; with none, there's no Create job (a direct request
      is refused, naming the jobs that hold them).
- [ ] Approving with "create the job automatically" on (JOB-01), and the NTF-04 "Create job"
      action, make one job with every free line; with none free, the action is skipped and says why.
- [ ] Cancelling a job frees its quote lines. Removing a quote line on the job form frees it too;
      lines added on the job are the job's own. Reopening a cancelled job is refused while any of
      its lines is in another live job, naming that job.
- [ ] A line is completed when its job is, and can't then join another job. A line on an invoice
      that isn't void keeps its job: no cancelling it or removing the line until that's voided.
- [ ] A line is never in two live jobs, enforced by the database: of two people taking it at
      once, the second is told which lines were taken and nothing is made.
- [ ] **Create invoice** on the quote bills every line of its completed jobs not yet on an invoice
      that isn't void (open question 1 for which figures), in one invoice linked to the quote and
      to each job it bills. Lines in unfinished jobs, and free lines, aren't billed; a job in
      progress bills nothing until it's completed. It can be used again as more jobs finish; with
      nothing to bill it isn't offered, and a direct request is refused with the reason. Quote
      discounts and taxes follow question 4; once all is billed, discounts add up to the quote's.
- [ ] "Ready to invoice" (jobs list, INS-01) counts a completed job until all its lines are on an
      invoice that went out; another job's invoice from the same quote no longer hides it.
- [ ] Staff quote page: each line shows its job and status, or "Not in a job", and its invoice;
      earlier cancelled jobs are listed. Primary (PLT-14): **Create invoice** when completed work
      is unbilled; else **Create job** when a line is free; else none. Job and invoice links are
      Secondary ("Jobs (2)" if several), replacing the interim handling of a cancelled job.
      Job page: "From Q-0004: 2 of 3 services", linking the quote's other jobs.
- [ ] Client quote page, once approved: each line says "Not booked yet", "Booked for Tue, Dec 3",
      "In progress", "Done", or "Billed" (its invoice's link when it has been sent), plus the
      approved total and "Billed so far". No job numbers, cancel reasons or internal notes. A
      line staff mark "Not going ahead" (open question 7) says so, with their note if any.
- [ ] The staff client timeline (CLI-05) records a job made from a quote (which services), a
      cancelled one freeing its services, and a line marked not going ahead.
- [ ] Existing data: each quote's lines belong to its job (free if that job is cancelled). Each
      job line copied from the quote is matched to its quote line where it can be, the rest are
      the job's own. Lines on an invoice that isn't void count as billed. No total of any quote,
      job or invoice changes; a test checks it on copied demo data.
- [ ] Data export (INS-02), new columns at the end only: quote lines get their live job and
      invoice; job lines the quote line they came from; invoices the quote and every job billed.
- [ ] Making jobs and invoices stays with people who have office access (Owner, Admin, custom
      roles, ACC-07). Members quoting assigned requests (QTE-07, QTE-08) see none of a quote's
      jobs or invoices; technicians see only their visit's job lines (JOB-04), as today. Pickers
      take only that quote's free lines; another business's are not found.
- [ ] Works at 360 px: the line picker, the quote page's per-line status, the client quote page.
- [ ] Tests: partial and repeated jobs; cancel, remove, reopen; the race; automatic jobs; repeated
      invoices, nothing to bill, discount rounding, billed lines blocking cancel; each Primary and
      client line state; the migration; export; roles; tenancy.

## Out of scope

- Splitting a line's quantity (question 2); moving lines between live jobs; deposits (backlog).

## Open questions

1. **(blocking)** Which figures does the quote's invoice use? Recommend the completed jobs' lines
   as they are, on-site changes and added lines included ("the total of completed jobs"),
   replacing PAY-01's "a quote's invoice bills its lines as agreed".
2. Can a line's quantity be split across jobs (6 of 20 windows now)? Recommend no: the line is
   the unit, done once; the job can still change its quantity on site.
3. One invoice per job, several jobs per invoice, or the quote once at the end? Recommend the
   quote's Create invoice bills all completed, unbilled jobs in one invoice, again as more
   finish; the job's own Create invoice (and NTF-04 "invoice the job") stays and bills that job.
4. Quote discounts and taxes? Recommend a percent discount applies to each job as it is; a fixed
   amount is shared by each job's share of the quote subtotal, the invoice billing the last line
   taking the rounding cent. Tax rates and "prices include tax" are copied as now.
5. Deposits and billing upfront? Recommend no deposits here (backlog); keep today's "Invoice the
   whole quote" in the menu, with a confirm, billing every unbilled line as agreed.
6. Jobs without a quote? Recommend no change. Does a job's Create invoice stay? Recommend yes
   (question 3), giving the lines and figures the quote's would for that job, never billed twice.
7. How does the client see a cancelled or dropped part? Recommend a cancelled job's lines read
   "Not booked yet"; staff can mark a free line "Not going ahead" (optional note the client
   sees; undo while free), which stops it counting as work to do. No cancel reasons shown.
8. Unbilled work and free lines: which is Primary? Recommend Create invoice; Create job Secondary.
