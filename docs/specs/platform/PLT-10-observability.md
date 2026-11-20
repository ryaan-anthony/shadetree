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

- **Errors:** everything goes through Rails' own reporter, `Rails.error`. Unhandled request
  errors arrive from Rails' executor; unhandled job errors from `ApplicationJob#perform_now`
  (and Solid Queue; each exception is reported once). `Observability::ErrorContext` adds release
  (`KAMAL_VERSION`), environment, request id/method/path, job class/id, business and user ids,
  drops controller and job objects, masks filtered keys and scrubs emails and phone numbers from
  messages; `ErrorSubscriber` logs each as a JSON line and calls `Observability.tracker`, the
  single hook for the tracker (unset; see `config/initializers/observability.rb`).
- **Logs:** Rails 8.1's structured events (`Rails.event`), no new gem. `STRUCTURED_LOGS` (on in
  production) gives one JSON line per request and job and turns off Rails' text lines and the
  "Started … for <IP>" line. `region` joined the filter list.
- **Performance:** `SLOW_REQUEST_MS` (1000) and `SLOW_QUERY_MS` (250) log warnings in every
  environment; requests carry `area` (staff, client, operator, public); queries their source line
  and SQL without literals.
- **Jobs:** `JobHealthCheckJob` every 10 minutes alerts (through `Observability.alert`, so the
  same hook) on failures in the last 10 minutes and on a backlog over `JOB_BACKLOG_THRESHOLD`
  (100) or `JOB_WAIT_THRESHOLD` seconds (600). The console home shows a "Background jobs" card.
- **Inventory:** [docs/security/personal-data-inventory.md](../../security/personal-data-inventory.md).
- **Not done, waiting on decisions:** the tracker (open question below), so alerts reach the log
  and console only; the external uptime check (needs PLT-09 hosting and a service choice); the
  cost record (with PLT-09's monthly cost table). The job criterion stays open until alerts
  reach the maintainer.

## Open questions

- Self-hosted vs hosted error tracking — cost vs maintenance; record in an ADR.
