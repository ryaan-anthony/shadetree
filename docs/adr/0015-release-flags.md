# 0015. In-house release flags on PostgreSQL

- **Status:** Accepted
- **Date:** 2026-11-14
- **Specs:** PLT-11

## Context

Specs span several PRs, so developers need to merge unfinished work dark and turn it on for a
test business, then a few beta businesses, then everyone, without a deploy. Flags must work
with PostgreSQL and the existing Solid Cache, with no new infrastructure.

## Options considered

1. **Flipper** (with the Active Record adapter). Mature, with groups, percentages and a web UI.
   But it brings three gems and its own tables, its UI needs operator authentication we don't
   have yet, and it has no notion of an owner or a removal date.
2. **Environment variables.** No runtime changes, and no per-business rollout.
3. **A small in-house module** (`Feature`): a YAML registry declaring each flag's owner and
   removal milestone, a `feature_flags` table for state, and rake tasks to change it.

## Decision

Option 3.

- A flag is off, on, on for a list of businesses, or on for a percentage of businesses. The
  percentage uses a stable bucket (`crc32(flag:business_id) % 100`), so raising it never turns
  a business off.
- State is cached for 30 seconds and the cache is cleared on change.
- Undeclared flags are off; checking one raises in tests and logs a warning in development.

## Consequences

- About 150 lines we own, plus tests.
- The operator console (OPS-04) can add a screen over `Feature.status` and the same methods.
- Revisit Flipper if we need actor groups beyond businesses, or flag audit history.
- **Cost:** none.
