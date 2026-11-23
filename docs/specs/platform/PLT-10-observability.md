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

- [x] Unhandled exceptions in web requests and background jobs are reported to an error tracker
      with release version, environment, and business identifier — but no client names, emails,
      phone numbers, addresses or document contents. *Sentry, live once `SENTRY_DSN` is set.*
- [x] Logs are structured, include a request ID, and filter sensitive parameters (passwords,
      tokens, client contact details, payment data).
- [x] An external uptime check monitors the health endpoint and a client-link page; alerts go
      to the maintainer. *Scoped (owner, 2026-11-22): Sentry's uptime monitor on production
      `/up`; the client-link page and staging are later (Out of scope).*
- [x] Background job failures and queue backlog beyond a threshold raise an alert. *Through
      Sentry, once `SENTRY_DSN` and the Cron alert rule exist: a message per problem and the
      production `job-health` Cron monitor.*
- [x] Basic performance visibility exists (slow requests, slow queries) for the staff app and
      client pages.
- [x] A personal-data inventory lists where client PII is stored and confirms none is sent to
      logs or monitoring tools.
- [x] Monitoring tools fit within free or low-cost tiers at launch scale (recorded). *Sentry:
      free Developer plan, $0 (5,000 errors/month, 1 user, 30-day history, 1 Cron monitor, 1
      uptime monitor; checked 2026-11-22), covering errors, job alerts and uptime.*

## Out of scope

- Product analytics (MKT-04, OPS backlog). Public status page.
- Later (free plan has one uptime monitor): polling `/up/jobs`, `/up/backup`, the client-link
  page (`/c/` + 32 × `1`, a safe 404) and staging. Free options then: Better Stack (10 monitors,
  3-minute checks), UptimeRobot (50, 5-minute; free-plan commercial use disputed).

## Decisions

- **No logging gem.** Rails 8.1's structured events and error reporter cover logs and plumbing.
- **Error tracking is Sentry's free tier** (owner, 2026-11-22; ADR 0027).
- **Privacy rules for the tracker** (owner, 2026-11-22): no client names, emails, phone numbers,
  addresses or document contents; no default PII; request params, bodies, cookies, headers,
  breadcrumbs and SQL scrubbed; the business by id only; the DSN only from the environment, and
  the tracker off without it; tracing off to stay in the free tier.
- **Uptime** (owner, 2026-11-22): Sentry's one included uptime monitor, on production `/up`.
- **Backups alert too** (owner, 2026-11-22): stale or untested backups, by `/up/backup`'s rule,
  raise a Sentry message (same repeat throttle) and fail the `job-health` check-in.
- **Sub-processor** (owner, 2026-11-22): connect now; add Sentry to the sub-processors page when
  the legal drafts are finalised (#274).

## Implementation notes

- **Errors:** everything goes through `Rails.error`: request errors from Rails' executor, job
  errors from `ReportsUnhandledErrors#perform_now` (ApplicationJob and both mail delivery jobs;
  Solid Queue reports too, each exception once). `Observability::ErrorContext` adds release
  (`APP_REVISION`), environment, request id/method/path, job class/id, business and user ids,
  drops controller and job objects and masks filtered keys; messages lose Postgres' DETAIL/HINT
  and email/phone-like values. `ErrorSubscriber` logs a JSON line (with 10 app backtrace frames)
  and calls `Observability.tracker`, the one hook for the tracker.
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
- **Tracker:** Sentry, fed only through the hook (its own request, job and error-reporter
  capture off), with a `before_send` scrubber as a second layer; tested through Sentry's test
  transport. `SENTRY_DSN` (secret) and `SENTRY_ENVIRONMENT` (var) go through the deploy's env file.
- **Job alerts:** `JOB_FAILED_THRESHOLD` (1) new failures; each kind of alert (failures, backlog,
  backups via `BACKUP_ALERTS`) repeats at most every `JOB_ALERT_REPEAT_MINUTES` (60), failures
  counted since the last one. Production checks in as `job-health` (error on backlog or backups;
  a stopped check shows as missed). Errors are capped at 10 an hour per class and place.
- **Uptime targets:** `/up` now; `/up/jobs`, `/up/backup` and `/c/` + 32 × `1` (never issued:
  a 404 through the client-page stack, recording no view) are tested for later. Runbook: Monitoring.

## Open questions

- ~~Self-hosted vs hosted error tracking?~~ Hosted: Sentry's free tier (owner, 2026-11-22).
