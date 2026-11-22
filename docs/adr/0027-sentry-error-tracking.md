# 0027. Errors and job alerts go to Sentry's free plan, scrubbed in the app

- **Status:** Accepted
- **Date:** 2026-11-22
- **Specs:** PLT-10

## Context

PLT-10 left one hook for an error tracker (`Observability.tracker`) and asked: hosted or
self-hosted? The owner decided (2026-11-22): Sentry's free tier, with strict privacy rules: no
client names, emails, phone numbers, addresses or document contents; `send_default_pii` off;
request params, bodies, cookies, headers, breadcrumbs and SQL scrubbed; the DSN only from
`SENTRY_DSN`, and Sentry off without it (development, test, CI).

The free Developer plan (checked 2026-11-22) has one user, 5,000 errors a month, 30 days of
history, one Cron monitor and one uptime monitor, with email alerts.

## Options considered

1. **Self-hosted** (Sentry, GlitchTip or Bugsink on the homelab): no quota, but another service
   to run and back up, and it fails together with the site it watches.
2. **Sentry's free plan**, with its SDK capturing on its own (Rack middleware, Active Job
   extension) and a `before_send` scrubber: least code, but events start from the raw request
   and job arguments, and the scrubber is the only line of defence.
3. **Sentry's free plan, fed only through our hook**: events start from the payload the app
   already sanitizes for its log, and the scrubber runs as a second layer.

## Decision

Option 3. `sentry-ruby` and `sentry-rails`, initialised only when `SENTRY_DSN` is set
(`config/initializers/observability.rb`). `Observability::SentryTracker` is the tracker:
exceptions become Sentry exceptions, `Observability.alert` becomes a warning message grouped by
its text. sentry-rails' request middleware is removed from the stack, its job extension skips
every adapter, its `Rails.error` subscriber stays off and the SDK's patches are disabled, and
`before_send` drops any error event our tracker didn't mark, so each error is sent once, from
`Observability::ErrorSubscriber`, and nothing else can send one. Each error class and place is
capped at 10 events an hour per process. No trace headers go out on outbound requests. `before_send` drops the request, user details (but the id),
breadcrumbs, frame variables and source lines; masks context, tags and extra by
`config.filter_parameters` plus a wider key list; and scrubs exception messages (emails,
phone-like numbers, link tokens and file addresses, file names, database row details, SQL
literals; for Mail, SMTP and Stripe errors also the values they quote). Tags carry the business id, never its
name. Release is `APP_REVISION` (the deployed commit), environment `SENTRY_ENVIRONMENT` or the
deploy's environment. Tracing, profiling, logs and sessions are off.

Job health uses the one Cron monitor: `JobHealthCheckJob` checks in as `job-health` every run,
`error` while jobs fail or the queue is backlogged, so Sentry also notices when the check stops
(workers down). Backlog messages repeat at most hourly to protect the quota. Backups too (owner,
2026-11-22): stale or untested ones (`/up/backup`'s rule) raise a message with the same throttle
and fail the check-in.

## Consequences

- Alerts reach the maintainer by email from Sentry; nothing in the repo names an address.
- The scrubber can't recognise a name inside free text: exception messages must not be built
  from client details. `test/lib/sentry_tracker_test.rb` sends real request, job, database and
  alert events through Sentry's test transport and fails on any personal detail.
- Past 5,000 errors a month events are dropped until the reset; the log keeps everything.
- Sentry is a new sub-processor (ids and scrubbed messages only). Owner, 2026-11-22: connect
  now; add Sentry to the sub-processors page when the legal drafts are finalised (#274).
- Uptime (owner, 2026-11-22): Sentry's one included uptime monitor, on production `/up`. The
  other targets (`/up/jobs`, `/up/backup`, a client-link page, staging) wait for more monitors.
- **Cost:** $0 on the Developer plan at launch scale; the Team plan ($26/month) if the quota or a
  second user is needed.
