---
id: JOB-12
title: '"On my way" with arrival time'
domain: jobs
milestone: M6
depends_on: [ACC-09, JOB-04, JOB-05, NTF-03, CLI-05]
---
# JOB-12 · "On my way" with arrival time

> Requirements: [06-jobs](../../plans/06-jobs.md) R20; [08-notifications](../../plans/08-notifications.md) R10

## Summary

One tap on My day tells the client a technician is on the way and when they'll arrive: an email
and a card on their visit page, with who's coming when team profiles are shown (ACC-09). Off
until the business turns it on.

## User stories

- As a technician leaving a job, I want to tell the next client I'm 30 minutes out in one tap.
- As a client, I want to know who is coming and roughly when, so I'm home to open the door.

## Acceptance criteria

- [ ] Settings → Messages → "Visit emails to clients" has an "On my way" switch, off by default
      on every plan and for existing businesses (tested). Off, no one sees the button.
- [ ] On My day and the visit's page, each assignee of a visit scheduled (not started, completed
      or cancelled) for today on the location's clock sees "On my way". Others, including
      unassigned office staff, are refused, with role and tenancy tests.
- [ ] It offers 15, 30, 45 or 60 minutes or "Pick a time" (later today, 5+ minutes ahead). The
      time is rounded to the nearest 5 minutes (10:47 + 30 → "about 11:15 AM", tested). A time
      outside the window, or 15+ minutes from an exact start, warns ("That's after the 9 AM–12 PM
      window") and can still be sent. Anytime visits don't warn.
- [ ] Sending doesn't start the visit (JOB-04's Start is separate); the row shows "On the way ·
      about 11:15 AM" with "Change time". All times are on the location's clock (CAT-07).
- [ ] Sending again updates the card at once; an "Updated arrival time" email goes only when the
      time is 10+ minutes from the one last emailed. Any assignee can update; the latest sender is
      named first. At most one send a minute and 5 a day per visit; the sheet says why.
- [ ] Clients see the sender plus active co-assignees with a first name ("Marcus and Dee are on
      the way"), each with photo or initial. Deactivated co-assignees are left out. With team
      profiles off, or a sender who is deactivated or has no first name: "Green Lawn Co. is on the
      way, arriving about 11:15 AM". Client pages and emails never use a full name or email.
- [ ] The email goes at once (not batched like JOB-05's), branded, with a plain-text part and
      fixed wording (no free-text message): arrival time, window, address, each person's photo
      (inside the email, like the logo), first name and title (ACC-09), one phone per person or
      the business's once, and a button to the visit page. Reply-to stays the location's contact
      email. It and its update join NTF-03's editable messages (subject and opening text).
- [ ] The visit page shows an "On the way" card with the same people and time; past the time it
      reads "should be with you any minute" for an hour, then goes. Starting, completing,
      cancelling or moving the visit (day or time changed) removes it with no extra email (JOB-05's
      email, if on, says what changed). Reassigning only updates the names.
- [ ] No usable email (none, bounced, suppressed): nothing is emailed and the sheet says so. It
      offers tap-to-call and tap-to-text (message filled in) only after a notice, "The client will
      see your own number", with the work or business phone to copy instead (tested). The time is
      still recorded. Erased clients (INS-02) get no button.
- [ ] Only confirmed senders can send (ACC-01). Sends share the business's 30-an-hour client email
      budget with quote and invoice sends; at the limit the email isn't sent, the card still
      updates, and the sender is told. Support viewing as a member (OPS-03) can't send.
- [ ] Each send and update is in the visit's history (who, time, emailed or not); the email is
      listed on the job (NTF-01); the first send is on the client timeline (CLI-05): "Marcus was
      on the way, arriving about 11:15 AM". The schedule and job page show "On the way".
- [ ] My day stays fast and works at 360 px, by keyboard and screen reader (the sheet is a
      dialog; the warning is announced); axe passes. SMS (backlog) can join under the same switch.
- [ ] Tests cover the example: a 9 AM–12 PM window, at 10:45 Marcus sends "30 min", and the email
      and card say "Marcus is on the way, arriving about 11:15 AM" with his photo and no warning.
      Also: "30 min" at 11:45 warns; small and large updates; two crew, one deactivated; no first
      name; profiles off; no email; unconfirmed sender; limits; cancel and move; DST; another zone;
      tenancy. Dev seeds have one visit on the way.

## Out of scope

- SMS (metered backlog, 08-notifications D2), live location, sending from the office, an
  automation trigger (NTF-04). Request follow-ups (JOB-06): they'd leak past JOB-08's Busy blocks.

## Implementation notes

- New visit history kind (the kinds have a database check) and a new `ClientEvent::KINDS` entry.
  Names go in the `<side>`/`<side>_ids` shape so `User#scrub_names_left_elsewhere` covers them, or
  are rendered from user ids when read. Subjects naming "Marcus" stay in sent-email records, as
  other sent subjects do. If the sheet records who it went to, client erasure scrubs it.

## Decisions

- Email plus the client's visit page card; SMS waits for its backlog spec (owner, 2026-11-22).
- A business-level switch only, no per-member opt-out (owner, 2026-11-22).
- One tap on My day for an assigned visit: 15, 30, 45 or 60 minutes or a custom time, with a
  warning outside the arrival window (owner, 2026-11-22).
- The sender "and Dee", each with a photo; sending doesn't start the visit; every plan; the
  location's clock (owner, 2026-11-22).
- The card stays an hour after the time; a small label on the schedule; the card is on the visit
  page (clients have no job page); exact visits warn at 15 minutes (owner, 2026-11-22).
- Updates email at 10+ minutes; no email offers tap-to-text from the tech's phone; at the email
  limit it isn't sent; one send a minute, 5 a day (owner, 2026-11-22).
- The own-number notice before tap-to-call or text; rounding to 5 minutes; off for existing
  businesses; fixed wording; follow-ups out of scope (review, 2026-11-22).

## Open questions

- None.
