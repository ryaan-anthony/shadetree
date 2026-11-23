---
id: JOB-05
title: Visit confirmations & reminders
domain: jobs
milestone: M3
depends_on: [JOB-02, NTF-01, PLT-12]
---
# JOB-05 · Visit confirmations & reminders

> Requirements: [06-jobs](../../plans/06-jobs.md) R13, R14

## Summary

No-shows and "I forgot you were coming" cost small businesses real money. Tell the client when a
visit is booked, changed or cancelled, and remind them the day before — with a link showing
when, where and how to reach the business.

## User stories

- As a client, I want a confirmation with the date and arrival window so that I can plan to be
  home.
- As a client, I want a reminder the day before.
- As an owner, I want to control which of these messages go out.

## Acceptance criteria

- [x] When a visit is scheduled, rescheduled or cancelled, the client receives an email (if the
      client has an email) using the business-branded layout.
- [x] A reminder email is sent the day before the visit at a sensible local time (business time
      zone), only for visits still scheduled.
- [x] Each email links to a client visit page (PLT-12 link) showing business, date, time or
      window, property address, visit instructions intended for the client, and business
      contact options. Cancelled visits show as cancelled.
- [x] Owners/Admins can turn each message type on/off in settings, and skip notification for an
      individual change ("don't notify client").
- [x] Rapid successive edits don't spam the client (changes within a short window are coalesced).
- [x] Sent messages are recorded per NTF-01 and visible on the job.
- [x] Tests cover timing (time zones, DST), suppression settings, coalescing and link scope.

## Implementation notes

- Part 1 (booked, moved and cancelled emails, the client's visit page, "don't notify client",
  coalescing, the list on the job) is one PR; the day-before reminder and the settings that turn
  each message off are part 2.
- **Coalescing:** a visit remembers what its client was last told (`client_told`: booked or
  cancelled, and when). A change sets the job's `client_notice_due_at` to 3 minutes out; when
  it's due, one email covers every visit of the job whose state differs from what the client
  knows. So several days booked at once are one email, a booking moved twice is one "moved"
  email, and a change undone in time (or a visit booked and cancelled) sends nothing. Mixed
  changes ("moved one, cancelled another") are one email too.
- **"Don't notify client":** a checkbox on the visit form and the cancel dialogs (job and visit),
  shown when the client has an email. Unticked, the change counts as what the client knows,
  unless an email about an earlier change is already due: that email then shows the visit as
  it is now. Completing a job doesn't email about the visits it cancels.
- Only someone who has confirmed their email can email clients (ACC-01); otherwise the form
  says so and nothing is sent. The business's hourly client email limit postpones a notice by
  15 minutes rather than dropping it.
- Only visits from today on are news; a past visit's changes aren't emailed.
- **Visit instructions** stay the crew's. A visit has a separate **Note for the client**, shown in
  their emails and on their page.
- The visit page is the visit's client link (PLT-12), one per visit, lasting until a month after
  the visit's day however often it moves.
- **Reminders** go out from 10 am the business's time the day before (`VisitRemindersJob`, hourly
  at :07), for visits still booked, once each; a visit moved to another day (or restored) is
  reminded again (a new time on the same day isn't). A client emailed about the visit since
  midnight (booked or moved that morning) isn't also reminded, and one whose email about it is
  still pending is looked at again the next hour. Runs missed for the rest of that day aren't
  made up at night. Fixed lead time, as recommended.
- **Settings:** Settings → Messages → "Visit emails to clients" turns booked, moved, cancelled
  and reminder emails on or off; with a kind off, its changes still count as what the client knows.
- The emails are recorded per NTF-01 against the job (`related: job`, kinds `visit_scheduled`,
  `visit_changed`, `visit_cancelled`, `visit_reminder`) and listed on the job page, with one
  about to go shown as pending.
- #289: a change is only queued for the client when it's a kind the business sends (and the
  client has an email); the job page promises the email only then ("We'll email Maria Lopez at
  9:38 PM", or "shortly" once that's passed), and explains the wait. No "send now".

## Decisions

- The visit-email switches (booked, moved, cancelled) live on Settings → Messages, not
  "Quotes, jobs & invoices": same settings, new place (owner, 2026-11-22).
- The day-before reminder's switch, in the same card, moved with them (coordinator; owner to
  confirm).

## Out of scope

- SMS confirmations/reminders, client confirmation/reschedule requests (backlog). "On my way"
  emails are JOB-12.

## Open questions

- Reminder lead time: fixed day-before vs configurable hours? Recommend fixed at launch.
- Should the client be able to reply "can't make it" from the visit page? Recommend backlog.
