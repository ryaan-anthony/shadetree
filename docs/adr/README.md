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
| [0002](0002-postgresql.md) | PostgreSQL is the primary database | Accepted; managed hosting superseded by 0023 |
| [0003](0003-tenancy-row-level-scoping.md) | Tenancy by row-level scoping in the application | Accepted |
| [0004](0004-tailwind-compiled-css.md) | Tailwind CSS compiled at build time | Accepted |
| [0005](0005-ui-partials-and-stimulus.md) | UI building blocks as partials and helpers, behavior in Stimulus | Accepted |
| [0006](0006-minitest.md) | Minitest, fixtures and Capybara for tests | Accepted |
| [0007](0007-solid-queue-jobs.md) | Solid Queue for background and scheduled work | Accepted |
| [0008](0008-active-storage-object-storage.md) | Active Storage on S3-compatible object storage | Superseded in part by 0023 |
| [0009](0009-hosting-kamal-vps.md) | Kamal on a VPS, with managed PostgreSQL | Superseded in part by 0023 |
| [0010](0010-pdf-headless-chrome.md) | PDFs rendered from HTML with headless Chrome | Accepted |
| [0011](0011-transactional-email-postmark.md) | Postmark for transactional email | Superseded by 0017 |
| [0012](0012-keep-devise.md) | Keep Devise for authentication | Accepted |
| [0013](0013-money-time-and-numbering.md) | Exact money, per-rate tax, UTC times and per-business document numbers | Accepted |
| [0014](0014-tenant-scoping-enforcement.md) | Tenant scoping enforced by default, opaque ids in URLs | Accepted |
| [0015](0015-release-flags.md) | In-house release flags on PostgreSQL | Accepted |
| [0016](0016-client-links.md) | One client-link mechanism, with derived tokens and per-link state | Accepted |
| [0017](0017-transactional-email-smtp.md) | Transactional email over SMTP | Accepted |
| [0018](0018-client-page-referrer-policy.md) | Client pages send Referrer-Policy: same-origin | Accepted |
| [0019](0019-hand-built-operator-console.md) | Hand-built operator console, with in-app two-factor and an append-only audit log | Accepted |
| [0020](0020-in-app-support-tickets.md) | Support tickets built into the app | Accepted |
| [0021](0021-inbound-support-email.md) | Inbound support email through Cloudflare Email Routing and a signed Worker post | Accepted |
| [0021](0021-stripe-connect-standard-direct-charges.md) | Client payments through Stripe Connect Standard, with direct charges on Checkout | Accepted |
| [0022](0022-subscription-billing-with-stripe.md) | Subscription billing with Stripe's hosted pages, mirrored from its events | Accepted |
| [0023](0023-homelab-vms-and-cloudflare-tunnel.md) | Staging and production on the owner's homelab VMs, deployed by GitHub Actions, behind a Cloudflare tunnel | Accepted |
| [0025](0025-staging-sends-real-email.md) | Staging sends real email; the mail sandbox is optional | Accepted |
