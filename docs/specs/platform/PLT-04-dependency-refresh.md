---
id: PLT-04
title: Dependency refresh
domain: platform
milestone: M0
depends_on: [PLT-02]
---
# PLT-04 · Dependency refresh

> Requirements: [01-platform](../../plans/01-platform.md) R6

## Summary

About a dozen automated dependency PRs are open and stale. Bring the app to current supported
versions in one coordinated pass, then configure updates so they arrive grouped and
manageable instead of as daily noise.

## User stories

- As the maintainer, I want one weekly, grouped dependency PR so that updates don't pile up.
- As a developer, I want to start new work on current, supported framework versions.

## Acceptance criteria

- [ ] Ruby, Rails and all gems/JS pins are on current supported releases at the time of the
      work; the app boots and the test suite passes.
- [ ] All stale automated dependency PRs are merged (via the refresh) or closed with a comment.
- [ ] Unused dependencies are removed (e.g. anything only needed by scaffolding that was never
      used).
- [ ] Automated updates are configured to run weekly and group minor/patch updates per
      ecosystem; security updates still arrive immediately.
- [ ] The Ruby version used locally, in CI, and in the container image come from one source of
      truth.
- [ ] A short upgrade note is added to the changelog/PR describing notable version jumps.

## Out of scope

- Swapping frameworks or databases (decided in PLT-01, executed in PLT-05/07).

## Open questions

- Should auto-merge be enabled for grouped patch updates once CI is green? Recommend yes after
  PLT-02 lands.
