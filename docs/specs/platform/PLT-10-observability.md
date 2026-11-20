---
id: PLT-10
title: Observability
domain: platform
milestone: M1
depends_on: [PLT-09]
---
# PLT-10 · Observability

> Requirements: [01-platform](../../plans/01-platform.md) R19, R22

## Summary

Know when something breaks before a business owner emails us, and have enough context to fix
it, without leaking client personal data into third-party tools.

## User stories

- As the operator, I want to be alerted when error rates spike, jobs fail repeatedly or the site
  is down so that I can respond quickly.
- As a developer, I want errors grouped with the request, business and release context.

## Acceptance criteria

- [ ] Unhandled exceptions in web requests and background jobs are reported to an error tracker
      with release version, environment, and business identifier — but no client names, emails,
      phone numbers, addresses or document contents.
- [x] Logs are structured, include a request ID, and filter sensitive parameters (passwords,
      tokens, client contact details, payment data).
- [ ] An external uptime check monitors the health endpoint and a client-link page; alerts go
      to the maintainer.
- [ ] Background job failures and queue backlog beyond a threshold raise an alert.
- [x] Basic performance visibility exists (slow requests, slow queries) for the staff app and
      client pages.
- [x] A personal-data inventory lists where client PII is stored and confirms none is sent to
      logs or monitoring tools.
- [ ] Monitoring tools fit within free or low-cost tiers at launch scale (recorded).

## Out of scope

- Product analytics (MKT-04, OPS backlog). Public status page.

## Decisions

- **No logging or tracker gem yet.** Rails 8.1's structured events and error reporter cover
  logs and plumbing; the tracker plugs into one hook once the open question is answered.

## Implementation notes

- **Errors:** everything goes through `Rails.error`: request errors from Rails' executor, job
  errors from `ReportsUnhandledErrors#perform_now` (ApplicationJob and both mail delivery jobs;
  Solid Queue reports too, each exception once). `Observability::ErrorContext` adds release
  (`APP_REVISION`), environment, request id/method/path, job class/id, business and user ids,
  drops controller and job objects and masks filtered keys; messages lose Postgres' DETAIL/HINT
  and email/phone-like values. `ErrorSubscriber` logs a JSON line (with 10 app backtrace frames)
  and calls `Observability.tracker`, the one hook for the tracker (unset).
- **Logs:** Rails 8.1's structured events, no new gem. `STRUCTURED_LOGS` (on in production):
  every line is JSON (`JsonLogFormatter`, tags in a field), one per request (requests no
  controller finished get theirs from `SecretPathLogger`) and per job, retry and discard; Rails'
  text lines and the "Started … for <IP>" line are off. Paths blank link tokens and Active
  Storage addresses; `region`, `signed_id` and `filename` joined the filter list.
- **Performance:** `SLOW_REQUEST_MS` (1000) and `SLOW_QUERY_MS` (250) log warnings everywhere;
  requests carry `area` (staff, client, operator, public); queries their source and literal-free SQL.
- **Jobs:** `JobHealthCheckJob` (every 10 minutes, priority -10) alerts through the same hook on
  failures newer than the last one alerted on (watermark in the cache) and on a backlog over
  `JOB_BACKLOG_THRESHOLD` (100) or a due job waiting over `JOB_WAIT_THRESHOLD` (600 s). Workers
  being down stops that check, so `/up/jobs` answers 503 for the uptime check; `/up` is unchanged.
  Console home: "Background jobs" card. `MIN(created_at)` on ready executions has no index (Solid
  Queue owns that schema; the table is small); revisit if it grows.
- **Inventory:** [docs/security/personal-data-inventory.md](../../security/personal-data-inventory.md).
- **Waiting on decisions:** the tracker (open question), so alerts reach the log and console
  only; the uptime check (PLT-09 hosting and a service); the cost record. The job criterion stays
  open until alerts reach the maintainer.

## Open questions

- Self-hosted vs hosted error tracking — cost vs maintenance; record in an ADR.
