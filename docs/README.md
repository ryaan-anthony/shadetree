# Shadetree documentation

This folder is the source of truth for what Shadetree is and what we are building next.
It replaces the original planning material in `.project/`, which is kept for reference only.

## How the docs are organized

| Layer | Where | Size | Purpose |
| --- | --- | --- | --- |
| Vision | [`plans/00-vision.md`](plans/00-vision.md) | < 500 lines | Mission, audience, principles, glossary, milestones, cross-cutting requirements |
| Requirements | [`plans/NN-<domain>.md`](plans/) | < 500 lines each | What each domain must do and why. Decisions and open questions live here. |
| Specifications | [`specs/<domain>/<ID>-<slug>.md`](specs/) | 30–60 lines (max 100) | One incrementally deliverable feature with acceptance criteria |
| Issues | GitHub Issues | short | One issue per spec: summary, acceptance criteria, link to spec |
| Mockups | [`mockups/`](mockups/README.md) | HTML | Clickable screens for M1–M5 specs, plus the design system reference |
| Audits | [`audits/`](audits/) | short | Triage of an outside audit against `main`: what's fixed, what's still true, and which spec covers it |

```
Requirement (plans/)  ──▶  Spec (specs/)  ──▶  Issue (GitHub)  ──▶  1..n Pull requests
```

## Domains

| # | Domain | Requirements | Spec prefix | Label |
| --- | --- | --- | --- | --- |
| 01 | Platform & engineering | [01-platform](plans/01-platform.md) | `PLT` | `area:platform` |
| 02 | Accounts & team | [02-accounts](plans/02-accounts.md) | `ACC` | `area:accounts` |
| 03 | Business setup & catalog | [03-catalog](plans/03-catalog.md) | `CAT` | `area:catalog` |
| 04 | Clients & requests | [04-clients](plans/04-clients.md) | `CLI` | `area:clients` |
| 05 | Quotes | [05-quotes](plans/05-quotes.md) | `QTE` | `area:quotes` |
| 06 | Jobs & scheduling | [06-jobs](plans/06-jobs.md) | `JOB` | `area:jobs` |
| 07 | Invoices & payments | [07-payments](plans/07-payments.md) | `PAY` | `area:payments` |
| 08 | Notifications & automations | [08-notifications](plans/08-notifications.md) | `NTF` | `area:notifications` |
| 09 | Plans & subscription billing | [09-billing](plans/09-billing.md) | `BIL` | `area:billing` |
| 10 | Operator console | [10-operator](plans/10-operator.md) | `OPS` | `area:operator` |
| 11 | Marketing site | [11-marketing](plans/11-marketing.md) | `MKT` | `area:marketing` |
| 12 | Insights & data | [12-insights](plans/12-insights.md) | `INS` | `area:insights` |

## Rules for writing specs

- **Describe outcomes, not implementation.** No table names, class names, gems, or code. The
  developer (human or agent) picking up the issue makes those calls and records significant
  ones as an architecture decision record (see `PLT-01`).
- **Each spec is shippable on its own.** It may take several PRs, but when its acceptance
  criteria pass, a user-visible (or developer-visible) capability exists.
- **Dependencies are explicit.** `depends_on` in the front matter lists spec IDs that must be
  done first. Anything not listed can be worked on in parallel.
- **Unknowns are written down.** Use the `Open questions` section. A question that blocks
  the work is marked **(blocking)**; resolve it in the issue before starting.
- **Specs evolve.** When a decision is made, update the spec and remove the question.

Use [`specs/_template.md`](specs/_template.md) for new specs. After editing specs, run
`script/plan/sync_issues --dry-run` to preview issue changes (see the script header).

## Status of this plan

Specs exist for milestones **M0–M5** (foundation through public launch). Work in **M6 (Growth)**
is listed as backlog in each requirements doc and will be specified once M4 ships.
