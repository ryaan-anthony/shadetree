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

A three-hour window is a long time to wait at home. With one tap on My day, a technician tells
the client they're on the way and when they'll arrive. The client gets an email and an "On the
way" card on their visit page, with the photo and first name of who's coming when the business
shows team profiles (ACC-09). It's off until the business turns it on.

## User stories

- As a technician leaving a job, I want to tell the next client I'm 30 minutes out in one tap.
- As a client, I want to know who is coming and roughly when, so I'm home to open the door.
- As an owner, I want this off unless I choose it.

## Acceptance criteria

- [ ] Settings → Messages → "Visit emails to clients" has an "On my way" switch, off by default,
      on every plan (`business_settings`). Off, no one sees the button.
- [ ] On My day and the visit's page, each assignee of a visit that's scheduled (not started,
      completed or cancelled) for today on the location's clock sees "On my way". Others,
      including unassigned office staff, are refused, with role and tenancy tests.
- [ ] It offers 15, 30, 45 or 60 minutes or "Pick a time" (later today, 5+ minutes ahead), then
      shows "Arriving about 11:15 AM", who it goes to, and Send. A time outside the window (or
      more than 15 minutes from an exact start) warns ("That's after the 9 AM–12 PM window") and
      still lets them send. Anytime visits don't warn.
- [ ] Sending doesn't start the visit: Start (JOB-04) stays separate and the status stays
      scheduled. The row shows "On the way · about 11:15 AM" with "Change time".
- [ ] Sending again is an update: the card changes at once, and an "Updated arrival time" email
      goes only when the time moves 10 minutes or more. Any assignee can update; the latest sender
      is named first. At most one send a minute and 5 a day per visit; the sheet says why.
- [ ] With several assignees the client sees the sender plus the rest ("Marcus and Dee are on
      the way"), each with their photo or initial. With team profiles off: no names or photos,
      "Green Lawn Co. is on the way, arriving about 11:15 AM".
- [ ] The email goes at once (not batched like JOB-05's), in the business-branded layout with a
      plain-text part: the arrival time, window and address, each person's photo (inside the
      email, like the logo), first name, title and phone (ACC-09), and a button to the visit
      page. It and its update join NTF-03's editable messages (subject and opening text;
      placeholders for names, arrival time and window; plan-gated as NTF-03 is).
- [ ] The client's visit page shows an "On the way" card with the same people and time. Once the
      time passes it reads "should be with you any minute" for an hour, then goes. It also goes
      when the visit is started, completed, cancelled or moved.
- [ ] Cancelling or moving the visit withdraws the notice with no extra email; JOB-05's cancelled
      or moved email (if on) says what changed. Reassigning updates the names and sends nothing.
- [ ] With no usable email (none, bounced, suppressed), nothing is emailed; the sheet says so and
      offers tap-to-call and tap-to-text from the tech's phone, message filled in. The time is
      still recorded. Erased clients (INS-02) get no button.
- [ ] Only confirmed senders can send (ACC-01). The email counts toward the business's hourly
      client email limit; at the limit it isn't sent (or postponed) and the sender is told.
      Support viewing as a member (OPS-03) can't send in either mode.
- [ ] Each send and update is in the visit's history (who, time, emailed or not), and the email
      is listed on the job (NTF-01). The first send is on the client timeline (CLI-05): "Marcus
      was on the way, arriving about 11:15 AM". The schedule and job page show "On the way".
- [ ] Every time (today, window, warning, client copy) is on the location's clock (CAT-07). Email
      is one channel: SMS (backlog) can join under the same switch without changing the steps.
- [ ] My day stays fast and works at 360 px, by keyboard and screen reader (the sheet is a
      dialog; the warning is announced); axe passes.
- [ ] Tests cover the example: a 9 AM–12 PM window, at 10:45 Marcus sends "30 min", and the
      client's email and card say "Marcus is on the way, arriving about 11:15 AM" with his photo
      and no warning. Also: "30 min" at 11:45 warns; small and large updates; two crew; profiles
      off; no email; unconfirmed sender; limits; cancel and move after sending; a DST day; a
      location in another zone; tenancy. Dev seeds have one visit on the way.

## Out of scope

- SMS (metered backlog, 08-notifications D2), live location or maps, sending for a technician
  from the office, an automation trigger (NTF-04).

## Decisions

- Email plus the card on the client's visit page; SMS waits for the SMS backlog spec
  (owner, 2026-11-22).
- A business-level switch only, no per-member opt-out (owner, 2026-11-22).
- One tap on My day for an assigned visit: 15, 30, 45 or 60 minutes or a custom time, with a
  warning outside the arrival window (owner, 2026-11-22).
- Several technicians: the sender "and Dee", each with a photo (owner, 2026-11-22).
- Sending doesn't start the visit; Start stays separate (owner, 2026-11-22).
- Every plan, on the location's clock (owner, 2026-11-22).
- The card stays an hour after the time passes (owner, 2026-11-22).
- A small "On the way" label on the staff schedule, no team notification (owner, 2026-11-22).
- The card is on the visit page; clients have no job page (owner, 2026-11-22).
- Exact-time visits warn beyond 15 minutes either side of the start (owner, 2026-11-22).
- An update emails only when the time moves 10 minutes or more (owner, 2026-11-22).
- No usable email: tap-to-text from the tech's own phone, not metered SMS (owner, 2026-11-22).
- At the hourly email limit it isn't sent, with no 15-minute delay (owner, 2026-11-22).
- At most one send a minute and 5 a day per visit (owner, 2026-11-22).

## Open questions

- None.
