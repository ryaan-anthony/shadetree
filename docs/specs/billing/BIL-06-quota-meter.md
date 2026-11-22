---
id: BIL-06
title: Quota meter
domain: billing
milestone: M6
depends_on: [BIL-03, BIL-05]
---
# BIL-06 · Quota meter

> Requirements: [09-billing](../../plans/09-billing.md) R14

## Summary

Usage shows today beside Send, on Home and in Settings → Plan, and a notice appears from 80%
(BIL-02, BIL-03). An owner should be able to see where they stand from any page without going
looking. Add a small meter at the foot of the sidebar, like a usage view: a bar with quotes used
of the limit and the reset date. The existing notices stay.

## User stories

- As an owner, I want to glance at the sidebar and know I've sent 3 of my 5 free quotes, so the
  limit never surprises me.
- As an office manager, I want to know when we're close, so I can tell the owner before a quote
  is held up.

## Acceptance criteria

- [ ] Every staff page (desktop sidebar and the phone drawer) shows the meter for the current
      business to people with office access or business settings (Owners, Admins, custom roles
      with either), always, however little is used: a label, a bar, "3 of 5" and "Resets Dec 1"
      (the reset date in the business's time zone, BIL-02). Others don't see it.
- [ ] The label says what it counts, as #289's wording does: "Free quotes this month", or
      "Starter quotes this billing period".
- [ ] The bar's state follows BIL-03: normal; approaching (from the warning threshold); at the
      limit, with "1 extra left"; then "Limit reached". Each state is said in words as well as
      colour, using the theme's tones.
- [ ] Unlimited plans show the count without a bar ("42 quotes sent this billing period · no
      limit"). A plan that doesn't include sending says so, linking to the plans.
- [ ] During a trial it shows the trial plan's limit, marked "(trial)", and "Trial ends Dec 3"
      when the trial ends before the reset (BIL-05). A lapsed or past-due business shows the plan
      it's on now.
- [ ] The meter links to Settings → Plan for people who can open it; for others it's plain text.
- [ ] It's readable by assistive technology as one meter with its value and limit ("3 of 5 free
      quotes used, resets December 1"), meets contrast on the sidebar, has no
      animation, and fits at 360 px.
- [ ] The count is the same number Settings → Plan and Home show, is current on each page load,
      and adds at most one fast query per page.
- [ ] BIL-03's notices (builder, send page, Home) and Home's allowance line are unchanged.
- [ ] Tests cover each state, unlimited and not-included plans, a trial, who sees it, the link
      rule, and that another business's usage is never shown.

## Out of scope

- Other limits (team size, storage) in the meter; they stay on Settings → Plan.
- Usage history charts (operators have history, BIL-02).
- Live updates without a page load.

## Decisions

- Shown to people with office access or business settings; technicians and quote-only members
  see usage beside Send (BIL-02) instead (owner, 2026-11-22).
- Numbers ("3 of 5"), not a percentage (owner, 2026-11-22).
- The reset date ("Resets Dec 1"), not a countdown (owner, 2026-11-22).
- Always shown, not only near the limit (owner, 2026-11-22).
- Unlimited plans show the count with no bar (owner, 2026-11-22).
