---
id: QTE-09
title: Quote progress for clients
domain: quotes
milestone: M6
depends_on: [JOB-09, PAY-06, CLI-05]
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
      split: "To do", "Booked for Tue, Dec 3", "Done", "Billed" (only once the invoice is sent,
      linking it) or "Not going ahead" with the note. A job with nothing booked reads "To do".
      A shortfall reads "Done: 5 of 6". No job numbers, cancel reasons or internal notes.
- [ ] Lines added during the work are listed under "Added during the work", each with what was
      billed for it.
- [ ] The page shows the approved total, billed so far, deposits (PAY-07, once they exist) and the
      amount still expected. With work dropped, it shows the approved total, the dropped amount
      and the new expected total. A short note explains that tax is worked out on each invoice,
      so it can differ by a few cents.
- [ ] Staff can mark a line, or its remaining to-do quantity, "Not going ahead", with an optional
      note the client sees. It can be undone while that quantity is still free. It counts in
      JOB-09's check, so it can't be booked, and reopening a job that held it is refused.
- [ ] Cancelling a job asks what happens to its work: **Rebook later** (back to "To do", the
      default) or **Not going ahead** (with the optional note).
- [ ] The quote closes when every line is done or not going ahead: question 1 for its status.
- [ ] The staff client timeline (CLI-05) records a job made from a quote (which services), a job
      cancelled (what was freed or dropped), work marked not going ahead or undone, and the quote
      closing.
- [ ] Erasing a client (INS-02) scrubs the "Not going ahead" notes with the documents' text.
- [ ] The quote PDF (QTE-02) stays as approved; progress is on the page only.
- [ ] Owners, Admins and ACC-07 roles with office access mark work not going ahead; technicians
      and quote-only members can't (tested). Another business's quote lines are not found.
- [ ] Works at 360 px: line statuses, the totals, and the mark dialog.
- [ ] Tests: each line state and split, a shortfall, added lines, totals with and without dropped
      work, Billed only after sending, mark and undo, cancel's two choices, closing, the
      timeline, erasure, roles, tenancy.

## Out of scope

- Client actions on progress (asking to drop or rebook work; they still call or email).
- Emails about progress; visit emails stay JOB-05's.

## Decisions

- Each line shows to do, booked for a date, done, billed, or not going ahead with its note; the
  page shows the approved total, billed so far, deposits and what's still expected
  (owner, 2026-11-22).
- Work that won't be done is marked "Not going ahead" with an optional note the client sees; the
  quote closes once every line is done or not going ahead (owner, 2026-11-22).

## Open questions

1. What does a quote show after partial work, and once closed? Recommend it stays Approved with
   "2 of 3 done" on the staff list and page, a "Partly done" filter, and Closed once everything
   is done or not going ahead.
2. Should the client see the dates of past visits on a done line? Recommend yes, "Done Tue, Dec 3".
3. Does the client get an email when work is marked not going ahead? Recommend no: staff tell
   them, and the page shows the note.
