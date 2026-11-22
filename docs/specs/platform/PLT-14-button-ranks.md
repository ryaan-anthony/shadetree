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
has no primary at all, and "Cancel job" is plain grey text. Settle on four ranks, use them on
every staff page, and make disabled controls look disabled. The look stays as it is. This is
about which existing style goes where. This spec also creates the shared page list that the
design-system checks run over. Triage: [#314 triage](../../audits/314-triage.md).

## User stories

- As an owner, I want the one green button on a page to be the next thing I should do.
- As an owner, I want anything that cancels or deletes to look dangerous before I click it.

## Acceptance criteria

- [x] The kit has four ranks, each shown on the style guide with its rule:
  - **Primary:** green, the next step in the workflow.
  - **Secondary:** white with a border, supporting actions.
  - **Tertiary:** borderless grey, for navigation, low-risk actions and Cancel.
  - **Destructive:** red text with a red border.
  - Beside these, a destructive dialog's confirm button is solid red, and the client pages'
    brand button is their Primary. That makes six button variants. The green inline text link
    isn't a button: it's only for actions inside a sentence.
- [x] Every staff page has at most one Primary in its header. A card or dialog may have its own
      Primary only when it is that region's single action (a rail card's "Export everything").
- [x] Moving to another record is never Primary. The quote page's Primary follows the
      Decisions. Approved quotes get their job and invoice links as Secondary.
- [x] Client page: "New quote" is the Primary, in the page header beside Edit. The Work card
      keeps "New job" and "New invoice" as Secondary (today they're borderless buttons).
- [x] These actions use Destructive: "Cancel job", "Disconnect" (Stripe), "Deactivate"
      (Team), "Archive" on a request, and every delete. Menus keep their items: Archive in the
      quote, service, location, tax-rate and client menus, and Delete (see Decisions).
- [x] Cancel on forms and dialogs is Tertiary everywhere.
- [x] An empty state's call to action uses the page action's own rank and wording.
- [x] Disabled controls look disabled everywhere: reduced contrast, no hover change, and the
      state exposed to assistive technology. A not-allowed cursor needs pointer events, which
      the kit turns off today. Keep it off and rely on contrast, or let pointer events through
      and block the click another way. Covers the pager's Previous and Next (the kit's and
      the Clients list's own) and the services list's move arrows.
- [x] **One shared page list.** The pages the accessibility check sweeps (fixtures, not seeds)
      become one list, plus each detail page in its main states. The axe tests and every
      design-system check (PLT-15 to PLT-22) use that list.
- [x] Integration tests render each page in the list as an Owner. They fail when a page
      header has more than one Primary, when a Cancel isn't Tertiary, or when a label above
      isn't Destructive.
- [x] A test fails when a view or layout writes kit button classes by hand instead of asking
      the kit (today: the sidebar's sign-out, the skip links, and the operator console).
      Unknown variants already raise.
- [x] Desktop (1280) and phone (390) screenshots of Home and the quote, job, invoice and
      client pages, with no visual change other than the ranks.

## Out of scope

- New colours or button shapes ("a new colour or font would be the wrong lever", #314).
- The quote and invoice builders' toolbars (Send is already their Primary).
- Client-facing pages beyond naming their brand button as Primary.

## Implementation notes

- Kit: `button_classes(:primary | :secondary | :tertiary | :destructive | :destructive_solid |
  :brand)`; `:ghost`, `:danger`, `:link` raise. `.text-action` is the in-sentence link.
  Disabled: sunken fill, `muted` text, no shadow or hover. A test bans hand-written `btn` classes.
- `test/support/staff_pages.rb` is the shared list (keys, kinds, `head:` opt-outs, ops pages).
  `design_system_test.rb` renders each page once and runs every registered `check`; the axe
  tests sweep the same list in three parts. `page_actions_test.rb` covers the Decisions.
- Confirm dialogs: `data-turbo-confirm-variant="destructive"` for red; a check matches it to the label.

## Decisions

- Home has no page-level Primary. It's an overview, and the rule is "at most one" (owner,
  2026-11-22).
- Tertiary is today's borderless grey button. The green text link stays only for actions
  inside a sentence ("None yet. Add instructions") and isn't a rank (owner, 2026-11-22).
- The quote page's job and invoice links become Secondary. Its Primary (owner, 2026-11-22; PAY-06
  restates it for quotes split across jobs and replaces the interim cancelled-job case, #353):
  - an approved quote with no job → **Create job** (today's button);
  - a job but no invoice → **Create invoice**;
  - otherwise no Primary. "Revise" on a quote with changes requested stays Secondary.
  - The earlier Draft case is dropped, because drafts open in the builder. #292's "Invoice
    INV-0001" link stays, as Secondary.
  - An approved quote whose job was cancelled → **Create job** too (owner, 2026-11-22).
- An open job with nothing booked has **Schedule visit** as its Primary; once a visit is
  booked, **Complete** (owner, 2026-11-22).
- Delete stays a red item in the client, draft quote and draft invoice menus, and a client's
  Archive stays in its menu (owner, 2026-11-22).
- Confirm dialogs use the Primary for safe actions and solid red only for Delete, Remove,
  Revoke, Disconnect, Deactivate, Suspend, Discard, Undo import, Cancel job or visit and
  Void; the message is the dialog's description (owner, 2026-11-22).
