---
id: PLT-02
title: CI quality gates & branch protection
domain: platform
milestone: M0
depends_on: []
---
# PLT-02 · CI quality gates & branch protection

> Requirements: [01-platform](../../plans/01-platform.md) R7, R8, R9

## Summary

Several developers and agents will open PRs in parallel. Every PR must prove it is safe to
merge — lint, security scans, and the full test suite — and `main` must only change through
reviewed, green PRs.

## User stories

- As a reviewer, I want automated checks to catch style, security and regression problems so
  that review focuses on behavior.
- As a developer, I want CI fast enough that waiting for it isn't a bottleneck.

## Acceptance criteria

- [ ] Every PR and every push to `main` runs: linting, static security analysis, dependency
      vulnerability audit (Ruby and JavaScript), unit/integration tests and system tests.
- [ ] Tests run in parallel where supported; median CI wall time is under 5 minutes.
- [ ] Failing system tests upload screenshots/logs as build artifacts.
- [ ] CI uses dependency caching and cancels superseded runs on the same branch.
- [ ] Branch protection on `main`: PR required, all checks required, at least one approval
      (configurable), branch must be up to date, no force pushes.
- [ ] A status badge and a short "CI" section exist in the README.
- [ ] A test-coverage report is produced and visible on PRs (no hard threshold yet).
- [ ] A scheduled weekly run catches newly disclosed vulnerabilities on `main`.

## Out of scope

- Deployment from CI (PLT-09).
- Preview environments per PR.

## Open questions

- Does the solo-maintainer phase need "1 approval" relaxed for the owner? GitHub allows admins
  to bypass; decide whether to allow it.
- Coverage threshold: introduce once the suite stabilizes (recommend after M2).
