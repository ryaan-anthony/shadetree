# 01 · Platform & engineering

## Purpose

Give every other domain a stable, secure, inexpensive foundation, and make the repository easy
for several developers and coding agents to work in at the same time without stepping on each
other.

## Current state (Nov 2026)

- Rails 8.1, Ruby 3.4.5, SQLite for all databases, Solid Queue/Cache/Cable, Propshaft, importmap,
  Hotwire, Devise (with confirmable), Minitest + Capybara, a deploy config with placeholder hosts
  (since replaced by the homelab deployment, ADR 0023).
- Tailwind is loaded from a CDN at runtime in every layout, with config inlined per layout.
- 27 tables exist; most (locations, service prices/taxes/fees per location, staff roles,
  notification triggers, service area restrictions, customer notification preferences) back no
  shipped feature.
- A basic CI workflow exists (brakeman, importmap audit, rubocop, tests). ~12 Dependabot PRs are
  open and stale.
- The original docs specify a different stack (PostgreSQL, Redis, Sidekiq, RSpec,
  ViewComponent). Nothing records which is intended.
- README is the Rails default; there is no setup guide, contribution guide, or agent guide.

## Requirements

### Engineering decisions
- **R1** Significant technical decisions are recorded as short architecture decision records
  (ADRs) in the repository, including the ones currently implicit: database, multi-tenancy
  isolation approach, CSS/asset pipeline, UI component approach, test framework, background
  processing, file storage, hosting.
- **R2** The documented stack and the running stack agree. Original docs that contradict
  decisions are marked superseded.

### Developer experience
- **R3** A new contributor can go from clone to a running app with seeded demo data with one
  documented command.
- **R4** Contribution rules are written down: branch naming, commit/PR conventions, how specs
  and issues relate, definition of done, and an agent guide for coding agents.
- **R5** Issue and PR templates enforce linking to a spec and listing acceptance criteria.
- **R6** Dependency updates are grouped and low-noise; the current backlog is resolved.

### Quality gates
- **R7** Every PR runs lint, security scans (Ruby and JS dependencies, static analysis), and the
  full test suite; failures block merge.
- **R8** `main` is protected: PRs required, checks required, linear history.
- **R9** Test suite stays fast enough to run on every PR (target < 5 min wall clock) and supports
  parallel execution.

### Architecture guardrails
- **R10** Tenancy: all business-owned data is scoped to a business by default; accessing another
  tenant's record is impossible through normal application code paths, and a shared test helper
  makes cross-tenant denial easy to assert.
- **R11** Conventions for money (exact, currency-aware), time (business time zone, stored in
  UTC), and identifiers exposed in URLs (non-guessable for anything client-facing).
- **R12** Client links: a single mechanism for secure, expiring, revocable links that let a
  client view or act on one document without an account. Used by quotes, invoices, visits.
- **R13** Feature flags: work can be merged dark and enabled per business or globally, so
  multi-PR features don't need long-lived branches.
- **R14** The schema contains only tables backed by shipped or in-progress specs. Speculative
  tables are removed and re-added when their spec is built.

### UI foundation
- **R15** CSS is built at deploy time (no runtime CDN), with one shared design-token set
  (colors, type, spacing) and three layouts: public/marketing, staff app (responsive, with
  mobile navigation), and client-facing (brandable, minimal).
- **R16** A small library of reusable UI building blocks (buttons, form fields, tables/lists,
  cards, empty states, flash messages, modals) so features look consistent without
  re-inventing markup.

### Operations
- **R17** Two environments: staging (auto-deploy from `main`) and production (manual promote).
- **R18** Automated, tested backups with documented restore; restore drill before launch.
- **R19** Error tracking, structured logs, uptime monitoring, and a health endpoint.
- **R20** Secrets are managed outside the repo and rotated on a documented process.

### Security
- **R21** Strict content security policy (possible once the CDN is gone), secure headers,
  rate limiting on authentication and public endpoints, bot protection on public forms.
- **R22** Personal data inventory: we know where client PII lives and it never reaches logs.

### Design system (admin audit #314)
- **R23** Buttons have four ranks (primary, secondary, tertiary, destructive). Each page has at
  most one primary, and it is the record's next step. Disabled controls look disabled.
- **R24** Every staff page has one page header with nothing repeated above it, and headings use
  one locked type scale.
- **R25** Staff pages use one of two layout containers (wide, form), and a detail page states
  each fact once.
- **R26** Status colours have one written meaning each, used for every status, and an event has
  one severity treatment everywhere. Colours come only from the theme's tokens.
- **R27** Money, dates, phones and quantities each have one format, used on every staff page.
- **R28** Tabs, segmented controls, search, empty states, toasts, banners, menus and file
  upload each have one kit pattern.

## Constraints

- Cost: the platform must run all tenants on modest infrastructure at launch (target < $50/month
  for staging + production before revenue).
- Simplicity: prefer Rails defaults and the "Solid" stack unless an ADR argues otherwise.
- No new runtime JavaScript frameworks; progressive enhancement only.

## Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | Rails conventions and defaults are the starting point for every choice. | Minimizes decisions per feature; matches the "small team" constraint. |
| D2 | Schema reset is allowed in M0. | No production data is believed to exist (open question G4). |
| D3 | Feature flags are built in M1, not M5. | They are what makes parallel, incremental delivery safe. |
| D4 | Stack choices (DB, test framework, components) are *not* made in this doc. | They are engineering decisions owned by `PLT-01` and its ADRs. |

## Specifications

| ID | Title | Milestone | Depends on |
| --- | --- | --- | --- |
| [PLT-01](../specs/platform/PLT-01-architecture-decisions.md) | Architecture decision records | M0 | — |
| [PLT-02](../specs/platform/PLT-02-ci-quality-gates.md) | CI quality gates & branch protection | M0 | — |
| [PLT-03](../specs/platform/PLT-03-contributor-experience.md) | Contributor & agent experience | M0 | — |
| [PLT-04](../specs/platform/PLT-04-dependency-refresh.md) | Dependency refresh | M0 | PLT-02 |
| [PLT-05](../specs/platform/PLT-05-ui-foundation.md) | UI foundation: build pipeline, layouts, components | M0 | PLT-01 |
| [PLT-06](../specs/platform/PLT-06-tenancy-guardrails.md) | Tenancy guardrails | M0 | PLT-01, PLT-07 |
| [PLT-07](../specs/platform/PLT-07-schema-reset.md) | Schema reset | M0 | PLT-01 |
| [PLT-08](../specs/platform/PLT-08-money-time-conventions.md) | Money, time & identifier conventions | M0 | PLT-01 |
| [PLT-09](../specs/platform/PLT-09-environments-deploy.md) | Environments, deploys & backups | M1 | PLT-01, PLT-02 |
| [PLT-10](../specs/platform/PLT-10-observability.md) | Observability | M1 | PLT-09 |
| [PLT-11](../specs/platform/PLT-11-feature-flags.md) | Feature flags | M1 | PLT-06 |
| [PLT-12](../specs/platform/PLT-12-client-links.md) | Client links | M1 | PLT-06, PLT-08 |
| [PLT-13](../specs/platform/PLT-13-security-baseline.md) | Security baseline | M5 | PLT-05, PLT-10 |
| [PLT-14](../specs/platform/PLT-14-button-ranks.md) | Design system: button ranks and page actions | M6 | PLT-05 |
| [PLT-15](../specs/platform/PLT-15-page-header-type-scale.md) | Design system: one page header and a locked type scale | M6 | PLT-05, PLT-14 |
| [PLT-16](../specs/platform/PLT-16-layout-containers.md) | Design system: two layout containers | M6 | PLT-05, PLT-14, PLT-15 |
| [PLT-17](../specs/platform/PLT-17-status-colour-language.md) | Design system: one status colour language and one severity per event | M6 | PLT-05, PLT-14 |
| [PLT-18](../specs/platform/PLT-18-formatting-copy.md) | Design system: one format per data type, and the remaining copy fixes | M6 | PLT-08, PLT-14 |
| [PLT-19](../specs/platform/PLT-19-tabs-toggles-search-menus.md) | Design system: tabs, segmented controls, search and menus | M6 | PLT-05, PLT-14 |
| [PLT-20](../specs/platform/PLT-20-each-fact-once.md) | Design system: each fact once on detail pages | M6 | PLT-14, PLT-15 |
| [PLT-21](../specs/platform/PLT-21-empty-states-feedback.md) | Design system: empty states, notifications, toasts and banners | M6 | PLT-14, PLT-17 |
| [PLT-22](../specs/platform/PLT-22-logo-upload-brand-note.md) | Design system: logo upload and where the brand colour applies | M6 | PLT-05 |

## Backlog (M6, not yet specified)

- Custom client-facing domains per business (`quotes.acmeplumbing.com`).
- Public API and outbound webhooks for integrations (Zapier/Make).
- Offline-capable technician view (PWA caching).
- Multi-region / data residency.

## Open questions

Decided in [`docs/adr`](../adr/README.md): PostgreSQL (0002), row-level tenancy (0003),
compiled Tailwind (0004), partials + Stimulus (0005), Minitest (0006), Solid Queue (0007), object
storage (0008), Kamal on a VPS with managed PostgreSQL (0009), headless-Chrome PDFs (0010),
Devise (0012), SMTP email (0017), homelab VMs behind a Cloudflare tunnel (0023, replacing parts
of 0002, 0008 and 0009).

1. ~~**Hosting provider**~~: decided by the owner (2026-11-20): their homelab VMs, provisioned in
   their op-works repository, one for staging and one for production (ADR 0023).
