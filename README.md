# Shadetree

[![CI](https://github.com/ryaan-anthony/shadetree/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ryaan-anthony/shadetree/actions/workflows/ci.yml)

Quotes, scheduling and payments for small service businesses. The plan, specs and mockups live
in [`docs/`](docs/README.md); conventions for contributors and coding agents are in
[`AGENTS.md`](AGENTS.md).

> A full setup guide arrives with PLT-03.

## CI

Every pull request and every push to `main` runs these checks. All of them must pass before a PR
can merge.

| Check | What it does | Run it locally |
| --- | --- | --- |
| Plan docs | Validates spec front matter, dependencies, sizes and links | `script/plan/lint` |
| Lint | RuboCop (Rails Omakase style) | `bin/rubocop` |
| Security | Brakeman static analysis, bundler-audit and importmap audit for known vulnerabilities | `bin/brakeman`, `bin/bundler-audit`, `bin/importmap audit` |
| Tests | Unit and integration tests in parallel, with a coverage summary on the run page | `bin/rails test` |
| System tests | Browser tests in headless Chrome; screenshots are uploaded when one fails | `bin/rails test:system` |

- A coverage report (`coverage/index.html`) is produced locally and uploaded as a build artifact.
  Set `COVERAGE=false` to skip it.
- A scheduled run every Monday re-checks `main` for newly disclosed vulnerabilities.
- A newer push to the same PR cancels the run that is already in progress.
- To ignore a vulnerability that doesn't apply, add it to `config/bundler-audit.yml` with a reason
  and the issue that will remove it.
