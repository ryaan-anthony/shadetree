# Shadetree

[![CI](https://github.com/ryaan-anthony/shadetree/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ryaan-anthony/shadetree/actions/workflows/ci.yml)

Quotes, scheduling and payments for small service businesses: request → quote → approval →
schedule → work → invoice → paid, from a phone, with a free plan. See
[`docs/plans/00-vision.md`](docs/plans/00-vision.md) for the product vision and
[`docs/mockups`](docs/mockups/README.md) for clickable screens.

## Stack

Rails 8.1 on Ruby 4.0, PostgreSQL, server-rendered HTML with Hotwire (Turbo and Stimulus) and import maps,
Devise for authentication, Solid Queue, Solid Cache and Solid Cable, Minitest and Capybara for
tests, and Kamal for deploys.

Decisions and their reasons are recorded as [architecture decision records](docs/adr/README.md):

| Area | Decision |
| --- | --- |
| Database | PostgreSQL, managed in production ([0002](docs/adr/0002-postgresql.md)) |
| Tenancy | Row-level scoping by business in the application ([0003](docs/adr/0003-tenancy-row-level-scoping.md)) |
| CSS | Tailwind compiled at build time, no CDN ([0004](docs/adr/0004-tailwind-compiled-css.md)) |
| UI | Partials and helpers; Stimulus and Turbo for behavior ([0005](docs/adr/0005-ui-partials-and-stimulus.md)) |
| Tests | Minitest, fixtures, Capybara ([0006](docs/adr/0006-minitest.md)) |
| Background work | Solid Queue, no Redis ([0007](docs/adr/0007-solid-queue-jobs.md)) |
| Files | Active Storage on S3-compatible storage ([0008](docs/adr/0008-active-storage-object-storage.md)) |
| Hosting | Kamal 2 on a VPS, managed PostgreSQL ([0009](docs/adr/0009-hosting-kamal-vps.md)) |
| PDFs | Same HTML as the web page, rendered by headless Chrome ([0010](docs/adr/0010-pdf-headless-chrome.md)) |
| Email | Postmark via Action Mailer ([0011](docs/adr/0011-transactional-email-postmark.md)) |
| Authentication | Devise, upgraded to 5.x in PLT-04 ([0012](docs/adr/0012-keep-devise.md)) |

## Getting started

**Prerequisites**

- Ruby 4.0.9 (the version in [`.ruby-version`](.ruby-version)); use any version manager
- PostgreSQL 16 or newer, running locally. `bin/setup` connects as your OS user by default;
  set `DATABASE_URL`, or `PGHOST`/`PGUSER`/`PGPASSWORD`, to use something else. Docker works:
  `docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:17` with
  `PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres`.
- Google Chrome, for system tests

**Setup**

```sh
git clone https://github.com/ryaan-anthony/shadetree.git
cd shadetree
bin/setup
```

`bin/setup` installs gems, prepares the database, loads demo data and starts the server at
<http://localhost:3000>. It's safe to run again any time. Options:

| Command | Does |
| --- | --- |
| `bin/setup --skip-server` | Everything except starting the server |
| `bin/setup --reset` | Drops and recreates the database first |
| `bin/dev` | Starts the server |

**Demo accounts** (development only): `owner@example.com`, `admin@example.com` and
`tech@example.com`, all with password `shadetree-demo-1`. They belong to the demo business
"Oakline Lawn & Landscape". Demo data lives in [`db/seeds/development.rb`](db/seeds/development.rb).

## Everyday commands

| Task | Command |
| --- | --- |
| Run unit and integration tests | `bin/rails test` |
| Run one file or line | `bin/rails test test/models/user_test.rb:12` |
| Run system (browser) tests | `bin/rails test:system` |
| Lint (and auto-fix) | `bin/rubocop` (`bin/rubocop -a`) |
| Security scans | `bin/brakeman`, `bin/bundler-audit`, `bin/importmap audit` |
| Validate planning docs | `script/plan/lint` |
| Preview issue changes after editing specs | `script/plan/sync_issues --dry-run` |
| Console | `bin/rails console` |

Tests write a coverage report to `coverage/index.html`. Set `COVERAGE=false` to skip it.

## How work is organized

```
docs/plans (requirements) → docs/specs (one deliverable each) → GitHub issue → 1..n pull requests
```

1. Pick an open issue whose blockers are all closed. Issues are grouped into milestones M0–M5.
2. Read its spec in [`docs/specs`](docs/specs) and the domain plan in [`docs/plans`](docs/plans).
3. Open small PRs that link the issue and tick off the acceptance criteria they satisfy.

[`CONTRIBUTING.md`](CONTRIBUTING.md) has the details (branches, commits, PR size, definition of
done, proposing an ADR). [`AGENTS.md`](AGENTS.md) is the short version for coding agents.

## CI

Every pull request and every push to `main` runs these checks. All of them must pass before a PR
can merge.

| Check | What it does | Run it locally |
| --- | --- | --- |
| Plan docs | Validates spec front matter, dependencies, sizes and links | `script/plan/lint` |
| Lint | RuboCop (Rails Omakase style) | `bin/rubocop` |
| Security | Brakeman static analysis, bundler-audit and importmap audit for known vulnerabilities | `bin/brakeman`, `bin/bundler-audit`, `bin/importmap audit` |
| Tests | Unit and integration tests in parallel, with a coverage summary on the run page | `bin/rails test` |
| System tests | Browser tests in headless Chrome; screenshots are uploaded when one fails | `bin/rails test:system` |

- A scheduled run every Monday re-checks `main` for newly disclosed vulnerabilities.
- A newer push to the same PR cancels the run that is already in progress.
- To ignore a vulnerability that doesn't apply, add it to `config/bundler-audit.yml` with a reason
  and the issue that will remove it.
