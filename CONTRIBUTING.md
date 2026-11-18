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

## Feature flags

Use a release flag when a spec takes more than one PR, or when a change should reach a few
businesses before everyone. Unfinished work then merges to `main` dark instead of living on a
long branch ([ADR 0015](docs/adr/0015-release-flags.md)).

1. Declare it in `config/feature_flags.yml` with a description, an owner and `remove_by` (the
   milestone by which the flag and the old code path are deleted). Checking an undeclared flag
   raises in tests.
2. Check it with `feature?(:name)` in controllers and views, or
   `Feature.enabled?(:name, business:)` in jobs and mailers. Keep checks at the edges (a route,
   a button, a branch in a controller), not deep in models.
3. Test both paths with `with_feature(:name) { … }` and `with_feature(:name, enabled: false) { … }`.
4. Roll out with `bin/rails "flags:enable_for[name,BUSINESS_UID]"`, then
   `"flags:percentage[name,25]"`, then `"flags:enable[name]"`. Use `"flags:disable[name]"` as the
   kill switch. `bin/rails flags:list` shows every flag, its state and when it's due to go.
5. Once a feature is fully on, open a PR that deletes the flag, its checks and the old path.
   Flags past their `remove_by` milestone are tech debt to schedule.

Flags are for releasing code. What a plan pays for is a separate concept (entitlements, BIL-01).

## Team notifications

Anything that should tell team members something ("Maria approved Q-0042") goes through
`NotificationType.deliver` (NTF-02). Each member gets an in-app notification; those who want that
type by email also get the email. To add a type:

1. Add a `Definition` to `NotificationType::ALL`. Give it a kind, the label and hint members see
   in their email settings, the permission its recipients need, whether it's emailed by default,
   and an icon.
2. Call `NotificationType.deliver(kind, business:, title:, path:, subject:, actor:)` where it
   happens. Pass `email: ->(user) { SomeMailer.with(...).some_email }` for a richer email than the
   generic one. For events about one person's own work, such as their visits, define the type
   with `audience: :named` and pass `to: users`.
3. Test who receives it, and that the person who acted doesn't.

`deliver` waits for the surrounding transaction to commit, so a change that's rolled back
notifies nobody. It never raises: problems are reported and can't break the action.

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

1. Copy [`docs/adr/template.md`](docs/adr/template.md) to the next number, for example
   `docs/adr/0013-feature-flags.md`, and add it to the index in `docs/adr/README.md`.
2. Fill in context, options considered, decision and consequences, including the cost for the
   free tier.
3. Open it as its own PR, or with the first code that depends on it. The PR is the proposal;
   merging it accepts the decision, so write `Status: Accepted`.
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
