# 0001. Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-01

## Context

The original plan in `.project/` described PostgreSQL, Redis, Sidekiq, RSpec and ViewComponent.
The running app uses SQLite, the Solid gems, Minitest and Tailwind from a CDN. Nothing recorded
which was intended. Several developers and coding agents will work in parallel, and each would
otherwise re-decide the stack, or follow the stale docs.

## Options considered

1. **Decisions in PR descriptions only.** Zero overhead, but hard to find later and easy to
   contradict.
2. **A wiki or external doc.** Drifts from the code and isn't visible to agents working in the
   repo.
3. **Lightweight ADRs in the repository.** One short Markdown file per decision, reviewed in PRs,
   versioned with the code.

## Decision

Keep ADRs in `docs/adr`, numbered, using [`template.md`](template.md). Merging the PR accepts the
decision. An ADR is never rewritten; a new ADR supersedes it. The index lives in
[`README.md`](README.md). Where an ADR conflicts with `.project/`, the ADR wins.

## Consequences

- Agents and new contributors have one place to learn the stack and its reasons.
- Every significant decision costs a short document. The definition of done
  (`CONTRIBUTING.md`) requires it.
- **Cost:** none.
