# Agent guide

Shadetree is a low-cost quoting, scheduling and invoicing platform for small service businesses
(Rails 8.1, server-rendered, Hotwire). This is the short version of
[`CONTRIBUTING.md`](CONTRIBUTING.md) for coding agents. Read both before your first PR.

## Where things are

- `docs/plans/`: requirements per domain (the why and what). Start with `00-vision.md`.
- `docs/specs/<domain>/`: one spec per deliverable feature, with acceptance criteria.
- `docs/mockups/`: clickable HTML screens per spec. This is design direction, not code to copy.
- `docs/adr/`: architecture decision records. Follow them; propose a new ADR to change one.
- GitHub Issues: one per spec (`[ID] Title`), with labels, milestones and "blocked by" links.
- `.project/`: the original 2025 plan. **Superseded**; ignore it unless asked.

## Workflow

1. Work on one issue whose blockers are closed. Read its spec and plan first.
2. Resolve **(blocking)** open questions in the issue before coding. Don't guess.
3. You make the implementation decisions; specs contain none. Record significant or
   hard-to-reverse decisions as an ADR.
4. Branch `<spec-id>-<slug>` (for example `qte-01-quote-builder`) from `main`.
5. Keep PRs small (under ~400 changed lines). Link the issue with `Part of #N` or `Closes #N`,
   and tick the acceptance criteria you satisfy.
6. Update the spec in the same PR if scope changes or a question gets answered, then run
   `script/plan/lint`.

## Non-negotiables

See `docs/plans/00-vision.md` → Cross-cutting requirements.

- **Tenancy:** a business's data is never visible to another business. Every data feature has a
  test proving cross-tenant access is denied.
- **Roles:** Owner, Admin and Technician, enforced server-side and tested.
- **Clients** (a business's customers) never have accounts; they act through secure client links.
- **Money and time:** money is exact (never floats); times are stored in UTC and shown in the
  business's time zone.
- **Mobile:** every page works at 360 px wide.
- **Secrets and data:** no secrets, client personal data or production data in code, logs,
  fixtures, screenshots or PRs.
- **CI:** lint, security scans, unit/integration and system tests must be green.

## Building UI

- Use the kit before writing new markup: browse `/styleguide` in development. Classes live in
  `app/assets/tailwind/components.css`, partials in `app/views/components`, helpers in
  `ComponentsHelper` (`button_classes`, `badge`, `card`, `empty_state`, `page_header`, `modal`,
  `pagination`) and `IconsHelper` (`icon "calendar"`, Feather names).
- Forms use the default builder's `f.field`, `f.check` and `f.submit_button`: labels, help,
  errors and ARIA come for free.
- Colours, radii and shadows come from `app/assets/tailwind/theme.css` tokens (`text-muted`,
  `bg-canopy`, `rounded-card`). Don't hard-code hex values or add a CDN.
- Pick the layout by audience: `app` (staff, under `Admin::`), `client` (business-branded, no
  staff chrome) or `marketing` (public). Confirmations use `data-turbo-confirm`, flashes render
  as toasts, behaviour goes in a Stimulus controller, not an inline `<script>`.
- `bin/dev` runs the Tailwind watcher; CI and the Docker build compile the CSS.

## Commands

| Task | Command |
| --- | --- |
| Set up (idempotent) | `bin/setup --skip-server` |
| Run the app | `bin/dev`; sign in as `owner@example.com` / `shadetree-demo-1` |
| Tests | `bin/rails test`, `bin/rails test:system` |
| Lint | `bin/rubocop` (`-a` to auto-fix) |
| Security | `bin/brakeman`, `bin/bundler-audit`, `bin/importmap audit` |
| Plan docs | `script/plan/lint`; `script/plan/sync_issues --dry-run` after editing specs |

Add demo data for new records to `db/seeds/development.rb`.

## Changing the plan

Edit specs or plans in a PR. After merge, `script/plan/sync_issues` updates the issues. Don't
edit generated issue bodies by hand; discussion belongs in issue comments.
