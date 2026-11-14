# Architecture decision records

Short records of significant technical decisions: what we chose, what we didn't, and why. They
let anyone (human or agent) build on agreed ground instead of re-deciding the stack in every PR.

## When to write one

Write an ADR when a decision is hard to reverse, affects more than one spec, or picks between
real alternatives: a new dependency or external service, a data-model pattern, a security
approach, a hosting change. Small, local choices belong in the PR description.

## How

1. Copy [`template.md`](template.md) to the next number: `NNNN-short-title.md`.
2. Fill in every section, including the cost for the free tier.
3. Open it in a PR, alone or with the first code that depends on it. The PR is the proposal;
   **merging it accepts the decision**, so write `Status: Accepted`.
4. Never rewrite an accepted ADR's decision. To change course, write a new ADR, set the old one
   to `Superseded by NNNN`, and link both ways.
5. Add it to the index below.

## Index

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-postgresql.md) | PostgreSQL is the primary database | Accepted |
| [0003](0003-tenancy-row-level-scoping.md) | Tenancy by row-level scoping in the application | Accepted |
| [0004](0004-tailwind-compiled-css.md) | Tailwind CSS compiled at build time | Accepted |
| [0005](0005-ui-partials-and-stimulus.md) | UI building blocks as partials and helpers, behavior in Stimulus | Accepted |
| [0006](0006-minitest.md) | Minitest, fixtures and Capybara for tests | Accepted |
| [0007](0007-solid-queue-jobs.md) | Solid Queue for background and scheduled work | Accepted |
| [0008](0008-active-storage-object-storage.md) | Active Storage on S3-compatible object storage | Accepted |
| [0009](0009-hosting-kamal-vps.md) | Kamal on a VPS, with managed PostgreSQL | Accepted |
| [0010](0010-pdf-headless-chrome.md) | PDFs rendered from HTML with headless Chrome | Accepted |
| [0011](0011-transactional-email-postmark.md) | Postmark for transactional email | Accepted |
| [0012](0012-keep-devise.md) | Keep Devise for authentication | Accepted |
| [0013](0013-money-time-and-numbering.md) | Exact money, per-rate tax, UTC times and per-business document numbers | Accepted |
| [0014](0014-tenant-scoping-enforcement.md) | Tenant scoping enforced by default, opaque ids in URLs | Accepted |
