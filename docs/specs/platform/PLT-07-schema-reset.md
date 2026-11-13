---
id: PLT-07
title: Schema reset
domain: platform
milestone: M0
depends_on: [PLT-01]
---
# PLT-07 · Schema reset

> Requirements: [01-platform](../../plans/01-platform.md) R14; vision "What changed"

## Summary

The schema contains about 20 tables built ahead of any feature (locations, per-location
pricing, taxes and fees, staff roles with JSON permissions, notification triggers, service area
restrictions, client notification preferences linked to users). Remove what no current spec
needs so each feature introduces exactly the data it requires, and fix the modeling decisions
the new plan reverses.

## User stories

- As a developer, I want the schema to reflect only real, shipped concepts so that I don't build
  on abandoned designs.
- As an agent, I want fewer dead models so that code search and reasoning are accurate.

## Acceptance criteria

- [ ] Only tables required by users, sign-in, businesses and memberships remain, plus framework
      tables; all other speculative models, migrations and fixtures are removed.
- [ ] Membership is a single concept with a role restricted to Owner, Admin, Technician (role
      enforcement itself lands in ACC-04).
- [ ] Plan/tier is no longer stored on the user (it moves to the business in BIL-01).
- [ ] Business address is ready to become structured (CAT-01 owns the final shape).
- [ ] Migrations are squashed into a clean baseline if no production data exists; otherwise
      data-preserving migrations are written.
- [ ] Models that remain have tests for validations and associations; existing tests pass.
- [ ] The decision is noted in the changelog and an ADR if the database engine changes here.

## Out of scope

- Adding new feature tables — each feature spec does that.
- Switching databases, unless PLT-01 decides to; if so, it happens here.

## Open questions

- **(blocking)** Confirm no production or staging data needs preserving (global question G4).
