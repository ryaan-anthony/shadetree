# Contributing to Shadetree

Thanks for helping. This guide covers how work flows from a spec to a merged pull request. It
applies equally to people and coding agents; agents should also read [`AGENTS.md`](AGENTS.md).

## Where the work comes from

| Layer | Where | What it is |
| --- | --- | --- |
| Requirements | [`docs/plans`](docs/plans) | What each domain must do and why, with decisions and open questions |
| Specs | [`docs/specs`](docs/specs) | One incrementally deliverable feature: summary, acceptance criteria, open questions |
| Issues | GitHub Issues | One issue per spec, labeled `area:<domain>`, in a milestone, with "blocked by" links |
| Pull requests | GitHub | One or more per issue |

Specs say **what** and **why**, never **how**. You make the implementation decisions; record
the significant ones as an ADR (see below).

## Picking up an issue

1. Choose an open issue in the earliest open milestone whose blockers are all closed.
2. Read the spec and the domain plan it links to.
3. If the issue is labeled `has-open-questions`, get the **(blocking)** questions answered in the
   issue thread before writing code. Other open questions can be answered as you go; record the
   answer in the spec.
4. Assign yourself (or comment) so nobody else starts the same work.

## Branches and commits

- Branch from `main`: `<spec-id>-<short-slug>`, lowercase. Example: `qte-01-quote-builder`.
  Use `fix-<slug>` or `chore-<slug>` for work without a spec.
- Commit messages: a short imperative subject (under 72 characters), a blank line, then why the
  change was made. Prefix the subject with the spec ID when there is one: `QTE-01: Add line
  item totals`.
- Keep `main` linear: rebase on `main` rather than merging it into your branch.

## Pull requests

- **Small and focused.** Aim for under ~400 changed lines excluding generated files. A spec that
  needs more becomes several PRs; merge partial work behind a feature flag (once PLT-11 lands)
  rather than holding a long-lived branch.
- **Link the issue.** Use `Part of #N` on intermediate PRs and `Closes #N` on the final one.
- **Tick the acceptance criteria** the PR satisfies, using the PR template.
- **Show the UI.** Include mobile (360 px) and desktop screenshots for any UI change.
- **CI must be green.** Lint, security scans, unit/integration and system tests all run on every
  PR (see the README).
- Update the spec in the same PR when scope changes or an open question gets answered, and run
  `script/plan/lint`.

## Definition of done

A spec's issue can close when:

- every acceptance criterion is met and covered by automated tests;
- data features include a test proving another business's data can't be read or changed;
- role rules (Owner, Admin, Technician) are enforced server-side and tested;
- UI works at 360 px wide, with empty and error states designed;
- CI is green with no new security warnings;
- user-facing copy is plain and consistent with the rest of the app;
- significant technical decisions are recorded as ADRs;
- the spec's open questions are resolved or explicitly deferred, and the spec is updated.

## Architecture decision records (ADRs)

Write an ADR when a decision is hard to reverse, affects more than one spec, or chooses between
real alternatives: a new dependency, a data-model pattern, an external service, a security
approach.

1. Copy the template in `docs/adr` (added by PLT-01) to the next number, for example
   `docs/adr/0012-pdf-generation.md`.
2. Fill in context, options considered, decision and consequences, including the cost for the
   free tier.
3. Open it as its own PR, or with the first code that depends on it. Mark it `Proposed`; it
   becomes `Accepted` when the PR merges.
4. To change a decision, write a new ADR that supersedes the old one. Don't rewrite history.

## Changing the plan

Edit specs or plans in a PR like any other change. After it merges, run
`script/plan/sync_issues` (or ask the maintainer to) so the issues match. Don't edit the
generated part of an issue body; discuss in comments.

## Code style and tests

- Ruby follows RuboCop Rails Omakase (`bin/rubocop -a` fixes most things).
- Tests use Minitest. Put unit tests next to their kind (`test/models`, `test/controllers`) and
  browser flows in `test/system`.
- Add demo data for new records to `db/seeds/development.rb` so `bin/setup` shows the feature.
- Never commit secrets, real client data or production data, including in fixtures and
  screenshots.

## Reporting bugs and proposing ideas

Use the issue forms: **Bug report**, **Chore / tech debt** or **Feature idea**. Accepted ideas
become specs. Report security problems privately through the repository’s **Security → Report a vulnerability** form, not in a public issue.
