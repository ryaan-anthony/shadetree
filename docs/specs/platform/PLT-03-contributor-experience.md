---
id: PLT-03
title: Contributor & agent experience
domain: platform
milestone: M0
depends_on: []
---
# PLT-03 · Contributor & agent experience

> Requirements: [01-platform](../../plans/01-platform.md) R3, R4, R5

## Summary

Make it trivial for a new developer or coding agent to set up the project, understand the
conventions, pick up an issue, and open a PR that meets the definition of done.

## User stories

- As a new contributor, I want one command to get a working app with demo data so that I can
  start on an issue within minutes.
- As a coding agent, I want a concise guide to the repository's conventions so that my PRs fit
  in without back-and-forth.
- As the maintainer, I want PRs to reference the spec and acceptance criteria they satisfy.

## Acceptance criteria

- [ ] README replaced with: what Shadetree is, stack summary, prerequisites, setup, running the
      app, running tests, linting, and links to `docs/`.
- [ ] A single setup command installs dependencies, prepares databases and loads realistic seed
      data (at least one business with members, services, clients, and documents as features
      land), and is idempotent.
- [ ] A contributing guide covers: branch naming, commit style, PR size guidance, how specs →
      issues → PRs relate, the definition of done, and how to propose an ADR.
- [ ] An agent guide (e.g. `AGENTS.md`, referenced by tool-specific files) summarizes
      conventions, commands, where docs live, and rules (no secrets, tenancy tests required).
- [ ] Issue templates exist for: spec-backed feature, bug report, and chore; PR template asks
      for the issue/spec link, acceptance criteria checklist, screenshots for UI, and test notes.
- [ ] Code owners are defined (initially the maintainer for everything).
- [ ] Editor and formatting conventions are shared (editorconfig or equivalent).

## Out of scope

- CI configuration (PLT-02), dependency policy (PLT-04).

## Open questions

- Should seed data be generated per feature as features land (recommended), with each spec
  responsible for adding seeds for its own records?
