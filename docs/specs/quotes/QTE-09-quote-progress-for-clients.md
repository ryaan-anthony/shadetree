---
id: QTE-09
title: Quote progress for clients
domain: quotes
milestone: M6
depends_on: [JOB-09, PAY-06, PAY-08, CLI-05]
---
# QTE-09 · Quote progress for clients

> Requirements: [05-quotes](../../plans/05-quotes.md) R13, R22

## Summary

Transparency is a first principle. Once a quote is approved and split into jobs (JOB-09), the
client's quote page shows where every service stands and what's been billed, so they never have
to ask. Work that won't be done is marked "Not going ahead", with a note the client sees, and
the quote closes once everything is done or not going ahead.

## User stories

- As a client, I want to see which services are booked, done and billed, and what's still to pay.
- As an owner, I want to drop the shed from the quote, tell the client why, and close the quote.

## Acceptance criteria

- [ ] On an approved quote's client page each line shows its status, split by quantity where it's
      split: "To do", "Booked for Tue, Dec 3", "Done Tue, Dec 3", "Billed" (only once the invoice
      is sent, linking it) or "Not going ahead" with the note. A job with nothing booked reads "To
      do"; a shortfall "Done: 5 of 6"; a progress-billed line "Billed $X of $Y". No job numbers,
      cancel reasons or internal notes.
- [ ] Lines added during the work are listed under "Added during the work", each with what was
      billed for it.
- [ ] The totals, from sent invoices only:
      - **Approved**: the latest approved total (QTE-10's changes included);
      - **Not going ahead**: the dropped amount, shown when there is some;
      - **Billed**: sent work and progress invoices, after progress credits and before deposit
        credits, so nothing billed early counts twice;
      - **Deposits**: paid, applied and left (PAY-07, once it exists);
      - **Still expected**: approved − not going ahead − billed.
      A note says tax is worked out on each invoice, so totals can differ by a few cents.
- [ ] Staff can mark a line, or the part of it still to do, "Not going ahead", with an optional
      note the client sees, and undo it while that part isn't in a job. JOB-09's check counts it,
      so it can't be booked, and a job reopening onto it is refused.
- [ ] Cancelling a job asks what happens to its work: **Rebook later** (back to "To do", the
      default) or **Not going ahead** (with the optional note).
- [ ] The quote stays Approved, showing "2 of 3 done" on the staff list and page, with a
      "Partly done" filter; it becomes **Closed** once every line is done or not going ahead.
- [ ] The staff client timeline (CLI-05) records a job made from a quote (which services), a job
      cancelled (what was freed or dropped), work marked not going ahead or undone, and the quote
      closing.
- [ ] Recurring quotes show JOB-10's series view instead, and close when the series ends.
- [ ] Erasing a client (INS-02) scrubs the "Not going ahead" notes with the documents' text.
- [ ] The quote PDF (QTE-02) stays as approved; progress is on the page only.
- [ ] Owners, Admins and ACC-07 roles with office access mark work not going ahead; technicians
      and quote-only members can't (tested). Another business's quote lines are not found.
- [ ] Works at 360 px: line statuses, the totals, and the mark dialog.
- [ ] Tests: each line state and split, shortfalls, progress, added lines, each total with and
      without dropped work, Billed only after sending, mark and undo, cancel's two choices,
      closing, recurring, the timeline, erasure, roles, tenancy.

## Out of scope

- Client actions on progress (asking to drop or rebook work; they still call or email).

## Decisions

- Each line shows to do, booked for a date, done, billed, or not going ahead with its note; the
  page shows the approved total, billed so far, deposits and what's still expected
  (owner, 2026-11-22).
- Work that won't be done is marked "Not going ahead" with an optional note the client sees.
  Cancelling a job offers Rebook later or Not going ahead (owner, 2026-11-22).
- The quote stays Approved with "2 of 3 done" and a "Partly done" filter, then becomes Closed
  once every line is done or not going ahead (owner, 2026-11-22).
- Done lines show their date. No email when work is marked not going ahead: staff tell the
  client, and the page shows the note (owner, 2026-11-22).

## Implementation notes

- `quote_line_items.not_going_ahead_quantity` and `.not_going_ahead_note`; the quantity is part
  of JOB-09's check. A closed quote is a status after approved, set when the last part finishes.
