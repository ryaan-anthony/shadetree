---
id: PLT-21
title: "Design system: empty states, notifications, toasts and banners"
domain: platform
milestone: M6
depends_on: [PLT-14, PLT-17]
---
# PLT-21 · Design system: empty states, notifications, toasts and banners

> Requirements: [01-platform](../../plans/01-platform.md) R28

## Summary

The admin audit (#314, items 11 and 13) found empty states ranging from the kit's
icon-and-sentence pattern (Taxes) to a bare "None yet." on Automations, and Home's "Nothing
booked today." is plain text. Unread notifications differ from read ones by a label only. The
kit has one toast and one banner, but no written rule for when to use each. Make the empty
state, toast and banner one pattern each, documented.
Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As a new owner, I want empty pages to tell me what goes there and how to start.
- As an owner, I want to see at a glance which notifications I haven't read.

## Acceptance criteria

- [x] **Empty states** use the kit's pattern wherever a page or a card's main content is empty:
      icon tile, title, one sentence, and at most one action (PLT-14). That covers
      Automations and their activity, Home's "Nothing booked today", My day's Today, the data
      log and message templates.
- [x] A one-line muted note stays only for a sub-list inside a card that has other content (a
      request's "Quotes: none yet").
- [x] Schedule says "Nothing booked this week" (or "this day") on every empty period, also when
      no later visit is booked. Today that line only shows with a next visit (#299).
- [x] **Notifications:** unread items have a bold title and a dot, and read items are muted.
      The "Unread" label (#280) stays, for assistive technology.
- [x] **Toast:** for the result of an action. Bottom centre, with an icon, the message and
      Dismiss. Success toasts fade after a few seconds, and errors stay until dismissed.
- [x] **Banner:** for a standing condition on a page. One icon, at most one link, and its tone
      from PLT-17. The style guide shows when each applies.
- [x] The guided tour's targets keep working. On My day the Today card keeps its target when
      empty, and on Home the setup checklist keeps its. The tour's tests pass unchanged.
- [x] An integration test over the shared page list (PLT-14), with empty fixtures where needed,
      fails when an empty page or card shows a bare note instead of the kit pattern.
- [ ] Desktop (1280) and phone (390) screenshots of Automations, Home and My day (empty), an
      empty Schedule week and Notifications.

## Out of scope

- A visible countdown on toasts.
- New icons or colours.
- Client-facing pages.

## Implementation notes

- Kit: `empty_state` (level 3 in a titled card). As on Taxes, Automations and Messages show their
  add button in the empty state, then in the card header once there's one. `.unread-dot`;
  `dismiss_controller.js` fades a success toast. Style guide `#feedback-rules`.
- Checks in `design_system_test.rb`: `empty_states_use_the_kit`, `empty_state_shape` and
  `banners_follow_the_pattern` (its `DECISION_BANNERS`, with sweep states for each).
  `StaffPages.empty` adds Home, My day, Schedule (week and day), Notifications, Automations,
  Messages and Your data. `feedback_patterns_test.rb` scans staff views for banner roles.
- Implementation decisions: "Unread" is screen-reader text beside the dot (as in the requests
  mockup), and a detail page's cards (a request's Quotes, a job's Visits) and the schedule's
  side cards keep one-line notes under the sub-list rule.
- Seeds: unread and read notifications for the demo owner; Rivera Pest Control
  (new@example.com) shows the empty states.

## Decisions

- Success toasts stay 10 seconds and wait while hovered, focused or the tab is hidden. Errors
  and Undo toasts stay until dismissed (owner, 2026-11-23).
- Live regions: a form's errors and an action that didn't happen (a stale save, an archived
  client picked) are danger banners with `role="alert"`. Warnings that come back from an
  action (booking clashes) use the polite region. Other banners are page content (owner,
  2026-11-23).
- Decision banners (location reprice, the $0.00 send, client matches) may carry more than one
  action. The Services and Invoices empty states keep their two (owner, 2026-11-23).
- The quote limit notice follows the owner's map (PLT-17): Nearly used warning, Limit reached
  danger.
