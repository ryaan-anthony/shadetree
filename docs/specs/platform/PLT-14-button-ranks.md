---
id: PLT-14
title: "Design system: button ranks and page actions"
domain: platform
milestone: M6
depends_on: [PLT-05]
---
# PLT-14 · Design system: button ranks and page actions

> Requirements: [01-platform](../../plans/01-platform.md) R23

## Summary

The admin design-system audit (#314, items 1 and 10) found that the loudest button on a page is
often not the most important one. The quote page's green button opens the job, the client page
has no primary at all, "Cancel job" is plain grey text, and the kit has seven button styles.
Settle on four ranks, use them on every staff page, and make disabled controls look disabled.
The look stays as it is. This is about which existing style goes where.
Triage and evidence: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want the one green button on a page to be the next thing I should do, so I
  never have to work out which of four equal buttons matters.
- As an owner, I want anything that cancels or deletes to look dangerous before I click it.

## Acceptance criteria

- [ ] The kit has four ranks, shown on the style guide with their rules: **Primary** (green,
      the next step in the workflow), **Secondary** (white with a border, supporting actions),
      **Tertiary** (text only: navigation, low-risk actions and Cancel), and **Destructive**
      (red text or a red border. Solid red only on the confirm button of a destructive dialog).
      The client layout's brand button is the client pages' Primary. Other variants are retired.
- [ ] Every staff page has at most one Primary in its header. A card or dialog may have its own
      single Primary only when it is that region's one action (a rail card's "Export everything").
- [ ] Moving to another record is never Primary. On detail pages the Primary is the record's
      next step, as listed in the spec's decisions once approved. Example: an approved quote
      with no invoice → "Create invoice". With nothing left to do there is no Primary.
- [ ] Client page: "New quote" is the Primary. "New job" and "New invoice" are the same
      Secondary rank as each other, not text links beside a bordered button.
- [ ] "Cancel job", "Disconnect", "Deactivate", "Archive" (when it hides work) and every
      delete use the Destructive rank, never plain grey text.
- [ ] Cancel on forms and dialogs is Tertiary everywhere.
- [ ] An empty state's call to action is the same button as the page's own action, not a second
      style of it.
- [ ] Disabled controls are visibly disabled on every page: reduced contrast, a not-allowed
      cursor, no hover change, and the disabled state exposed to assistive technology.
      Covers pagination's Previous/Next (including the Clients list's own pager) and the
      services list's move arrows.
- [ ] A test signs in as an Owner, visits every staff page in the sweep the accessibility
      check uses, plus each detail page in its main states, and fails when a page header has
      more than one Primary, a Cancel isn't Tertiary, or a destructive label isn't Destructive.
- [ ] A test fails if a view asks the kit for a retired variant.
- [ ] Desktop (1280) and phone (390) screenshots of Home, the quote, job, invoice and client
      pages before and after, with no visual change other than the ranks.

## Out of scope

- New colours or button shapes (the audit: "a new colour or font would be the wrong lever").
- Toolbars inside the quote and invoice builders (their Send button is already the Primary).
- Client-facing pages beyond renaming their brand button as Primary.

## Open questions

- Home's Primary? **Recommendation:** none. Home is an overview and each card has its own next
  step. The rule is "at most one", so zero is allowed.
- The quote page once a job exists: is the job link Secondary, and what's Primary?
  **Recommendation:** the job and invoice links become Secondary. Primary follows the record's
  state: Draft → Send; Changes requested → Revise; Approved without invoice → Create invoice;
  otherwise none. This keeps #292's rule that an invoiced quote shows "Invoice INV-0001", not
  "Create invoice".
- Which style is Tertiary? **Recommendation:** today's borderless grey button. Today's green
  text link stays only for actions inside a sentence ("None yet. Add instructions") and isn't
  a rank.
