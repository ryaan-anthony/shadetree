# Agent & contributor guide

Shadetree is a low-cost quoting, scheduling and invoicing platform for small service
businesses (Rails, server-rendered, Hotwire). This file tells coding agents and new contributors
how work is organized. A fuller contributing guide arrives with spec PLT-03.

## Where things are

- `docs/plans/` — requirements per domain (the *why* and *what*). Start with `00-vision.md`.
- `docs/specs/<domain>/` — one spec per deliverable feature, with acceptance criteria.
- GitHub Issues — one issue per spec (`[ID] Title`), labeled `area:<domain>`, grouped into
  milestones M0–M5, with "blocked by" links between issues.
- `.project/` — the original 2025 plan. **Superseded**; reference only.

## How to pick up work

1. Pick an open issue whose blockers are all closed. Read its spec and the domain plan.
2. Resolve any **(blocking)** open question in the issue thread before writing code.
3. Make the implementation decisions yourself. Specs deliberately contain no implementation
   details. Record significant or hard-to-reverse decisions as an ADR (see PLT-01).
4. Open one or more small PRs. Each PR links the issue (`Part of #N` or `Closes #N` on the
   last one) and ticks the acceptance criteria it satisfies.
5. Large features merge dark behind a feature flag (once PLT-11 lands) instead of living on a
   long branch.

## Non-negotiables (see `docs/plans/00-vision.md` → Cross-cutting requirements)

- Tenancy: business data is never visible across businesses. Every feature has a test proving
  cross-tenant access is denied.
- Roles: Owner, Admin, Technician. Authorization is enforced server-side and tested.
- Clients (a business's customers) never have accounts; they act through secure client links.
- Money is exact; times are stored in UTC and shown in the business's time zone.
- No secrets, client personal data, or production data in code, logs, fixtures or PRs.
- Every page works at 360 px wide.
- CI (lint, security scans, tests) must be green.

## Commands

- `bin/setup` — install and prepare the app
- `bin/dev` — run the app locally
- `bin/rails test` and `bin/rails test:system` — tests
- `bin/rubocop` — lint; `bin/brakeman` — security scan
- `script/plan/lint` — validate docs/specs (front matter, dependencies, sizes, links)
- `script/plan/sync_issues --dry-run` — preview GitHub issue changes after editing specs

## Changing the plan

Edit the spec (or plan) in a PR, run `script/plan/lint`, and after merge run
`script/plan/sync_issues` so issues reflect the change. Don't edit generated issue bodies by
hand; discussion belongs in issue comments.
