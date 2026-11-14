---
id: PLT-01
title: Architecture decision records
domain: platform
milestone: M0
depends_on: []
---
# PLT-01 · Architecture decision records

> Requirements: [01-platform](../../plans/01-platform.md) R1, R2

## Summary

The stack that the original docs describe and the stack that actually runs disagree, and none
of the choices are written down. This spec establishes a lightweight ADR practice and records
the foundational decisions so every later spec builds on agreed ground.

## User stories

- As a developer or coding agent, I want to know which database, test framework, CSS approach
  and job system to use so that I don't re-litigate them in every PR.
- As the product owner, I want trade-offs written down so I can revisit them knowingly.

## Acceptance criteria

- [ ] An ADR format and index exist in the repository; adding an ADR is documented in the
      contributor guide.
- [ ] Accepted ADRs exist for at least: primary database and backups; multi-tenancy isolation
      approach; CSS/asset pipeline; reusable UI component approach; test framework and test
      types; background jobs and scheduled work; file storage; hosting/deploy target; PDF
      generation approach; transactional email provider.
- [ ] Each ADR states context, options considered, decision, consequences, and cost impact
      for the free tier.
- [ ] The original `.project/` docs are marked superseded where they conflict.
- [ ] The decisions are reflected in the README's "stack" section.

## Out of scope

- Implementing the decisions (that happens in PLT-05, PLT-06, PLT-07, PLT-09 and feature specs).
- Payment provider choice (owned by PAY-03 / BIL-04, though an ADR may be written here).

## Open questions

Resolved in [`docs/adr`](../../adr/README.md) (Nov 2026):

- Database: PostgreSQL ([ADR 0002](../../adr/0002-postgresql.md)); the switch happens in PLT-07.
- Test framework: keep Minitest ([ADR 0006](../../adr/0006-minitest.md)).
- Components: partials and helpers, no component library ([ADR 0005](../../adr/0005-ui-partials-and-stimulus.md)).
- PDF memory: one render at a time on the VPS, moveable to a worker ([ADR 0010](../../adr/0010-pdf-headless-chrome.md)).
