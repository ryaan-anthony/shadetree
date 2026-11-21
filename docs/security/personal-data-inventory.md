# Personal-data inventory

> PLT-10 (R22). Where personal data lives in Shadetree, how long it stays, and what keeps it out
> of logs, monitoring and analytics. Update it in the same PR as any feature that stores,
> sends or logs personal data. Last reviewed: 2026-11-21.

**Clients** are a business's customers (no accounts). **Users** are business staff and
operators. **Visitors** use the public site and forms. A client's data belongs to the business;
erasing a client (INS-02, `ClientErasure`) removes or scrubs everything listed under Clients.

## Database (primary)

| Whose | Where (table: columns) | Kept |
| --- | --- | --- |
| Client | `clients`: display_name, company_name, notes, tags, search_text | Until erased or the business is deleted (OPS-04) |
| Client | `client_contact_methods`: value, normalized (emails, phones), label | Same |
| Client | `properties`: address lines, city, region, postal_code, access_notes | Same |
| Client | `client_notes.body`, `client_events.data`, `client_link_events.device` (coarse, e.g. "Phone · Safari") | Same |
| Client | `service_requests`: contact_name, contact_email, contact_phone, address, description, timing; `service_request_notes.body` | Same |
| Client | `quotes` / `invoices`: title, message, terms, internal_notes; `jobs`: title, instructions, internal_notes; `visits`: instructions, client_note; line items; `*_revisions.snapshot` | Same (financial records keep their numbers and totals after erasure) |
| Client | `visit_notes.body` (technicians' notes, can describe the client or property) | Same |
| Client | `quote_responses`: signer_name, email, message, ip_address, user_agent, signature, snapshot (the IP is evidence: in the "Quote responses" export, shown on no page) | Same; a full-export zip holding that CSV, IPs included, is deleted 7 days after it's made |
| Client | `quote_sends` / `invoice_sends`: recipient, cc; `email_messages`: to, subject, error; `payments`: reference, note, method_detail (PAY-04: card brand and last four digits, never the card number) | Same |
| Client | `email_suppressions.email` | Kept after erasure, so a bounced or complaining address isn't mailed again (privacy notice) |
| Client | `client_imports`: headers, examples, preview_rows, problems | Rows cleared after the 7-day undo window; abandoned uploads deleted after 2 days |
| Client | `notifications`: title, body (can name a client) | 90 days |
| Client | `automation_runs.log`, `quote_events` / `invoice_events` / `visit_events` `.data` | With the business |
| User | `users`: email, unconfirmed_email, first_name, last_name; `invitations.email`; `business_users.notification_emails` | Until the account or business is deleted |
| User | `user_sessions`: ip_address, user_agent; `audit_entries`: operator_email, ip_address, user_agent | Sessions until signed out or expired; the audit log is append-only |
| User | `data_exports.requested_by_email`; `operator_notes.body`, `support_messages.body` (may quote client details a business pasted) | With the business |
| Business | `businesses` / `locations`: email, phone, address (business contact details, often a sole trader's own) | With the business |
| User / anyone | `action_mailbox_inbound_emails`: envelope_from, envelope_to, auth_results (sender's domain and address), plus the raw message file (OPS-05 support email: whatever the sender wrote) | 14 days after processing (Action Mailbox incineration); `PurgeInboundEmailsJob` removes anything older than 14 days. By design these survive account or business deletion and client erasure for up to those 14 days |
| Business | Stripe (BIL-04) holds the billing email, address and card; Shadetree keeps only `businesses.stripe_customer_id`, `subscriptions` and `billing_events` (plan names, amounts, invoice numbers) | With the business; Stripe keeps its invoices |
| Business | `payment_accounts`: the Stripe account id and its status (no names or bank details; Stripe holds those) | With the business; deleting it disconnects the account first |
| — | `connect_events`: Stripe event id, type, account id and the few fields acted on (amounts, ids, status); no names, emails or card details, and the raw payload isn't stored or logged | 90 days |
| Visitor | `contact_messages`: name, email, business_name, body, ip_address, user_agent | IP and browser 30 days; spam 30 days; messages 2 years |

## Files (Active Storage, ADR 0008: local disk today; object storage in staging and production once PLT-09 lands)

Visit photos, job and document attachments, request photos, stored quote and invoice PDFs and
their revisions, raw support email (`message.eml`, 14 days, see above), client import uploads (CSV), full data-export zips (deleted when the 7-day link
expires), support-ticket files, business logos. Photos are stripped of location metadata
(PLT-13). File keys are random, but `active_storage_blobs.filename` keeps the uploaded name,
which can name a client ("Smith invoice.pdf"); file addresses (signed ids, then that name) are
blanked in logs.

## Other stores

- **Queue database (Solid Queue):** job arguments are ids and global ids. Exceptions: Devise
  emails carry their one-time token, and `AnalyticsEventJob` carries a visitor's IP and browser,
  until the job finishes (finished jobs are cleared after a day; failed ones stay until retried
  or discarded). Client email jobs don't log their arguments.
  `solid_queue_failed_executions.error` keeps a failed job's raw exception message and
  backtrace, which can include database row details or an address; only operators reach it, and
  retrying or discarding the job removes it.
- **Cache and cable databases:** no personal data is written deliberately; rebuildable.
- **Backups (PLT-09, PR #134, not live yet):** nightly `pg_dump` of the primary database and a copy of the files
  bucket, in a separate backup bucket: 30 daily dumps, 12 monthly. An erased client stays in
  older backups until they age out; a restore must re-run erasures done since the dump.
- **Email:** outgoing email (quotes, invoices, visit notices, receipts) contains client names,
  addresses and document content and passes through the email provider (ADR 0017), named on
  the sub-processors page.
- **Incoming support email (OPS-05, ADR 0021):** passes through Cloudflare Email Routing and
  an Email Worker, which forwards a copy to the human support inbox and posts it to the app.
  The app logs only an outcome and record ids (`inbound_email.*`, `support_mail.received`),
  never addresses, subjects or bodies (`test/integration/inbound/support_emails_test.rb`).
- **Third parties:** hosting provider (everything above), Cloudflare (incoming support email), email provider, Stripe (billing
  contacts and payment details, once BIL-04/PAY online payments ship). See
  `/legal/subprocessors`. No other service receives client data.

## Logs and monitoring

- **Request parameters** are filtered (`config/initializers/filter_parameter_logging.rb`):
  passwords, tokens, secrets, emails, phones, names, addresses (including region), notes, tags,
  search terms, and every free-text field of the public forms, quote sends and answers.
  The same list masks those attributes in `inspect` and in Rails' structured events.
- **Link tokens and file addresses** in paths (`/c/:token`, `/invitations/:token`,
  `/rails/active_storage/…`) are blanked, and email addresses in paths masked (`SecretPathLogger`,
  `Observability.path`).
- **Structured logs (production):** every line is JSON; one per request (request id, method,
  filtered path, controller, status, durations, business and user ids) and per job, retry and
  discard; no parameters and no IP address. Rails' text lines, which can quote exception
  messages, a mail server's reply or the client's IP, are switched off
  (`config/initializers/observability.rb`). The one deliberate exception: abuse lines (rate
  limits, bot checks; `AbuseProtection`) log the IP address and path (tokens blanked), to
  investigate attacks.
- **Errors and alerts** (`Observability::ErrorContext`, `ErrorSubscriber`): context is ids,
  global ids and class names only (controller and job objects are dropped); keys on the filter
  list are masked; exception messages lose Postgres' DETAIL/HINT (the failing row or key values)
  and have email addresses and phone-like numbers replaced.
  The same sanitized payload is what the error tracker will receive once one is chosen (PLT-10
  open question). Slow-query lines have literal strings removed from the SQL.
- **Tests:** `StructuredLogsTest` signs in and creates a client with distinctive details and
  fails if any of them, or a link token, reaches the log; `ObservabilityTest` checks error
  reports and slow queries the same way.
- **Known gaps:** development logs are verbose by design (local data only). There is no proxy
  log on the VMs (ADR 0023: Puma serves the tunnel directly). Cloudflare sees request paths,
  client-link tokens included, at its edge; keep Cloudflare logging features that store full
  URLs off. A tracker
  SDK that subscribes to `Rails.error` itself sees the raw exception; configure it to send
  `Observability.scrub(message)` instead.

## Analytics (MKT-04)

Self-hosted Plausible, cookieless, on our own servers (not a third party). Verified in code
(`app/models/analytics.rb`, `app/views/layouts/marketing.html.erb`, `AnalyticsEventJob`):

- The page-view script loads only on marketing pages that opt in (`content_for :analytics`),
  never in the staff app, operator console or client pages (layouts `app` and `client` don't
  include it), and never on pages with tokens.
- Server-side funnel events send only an event name and a fixed, id-free URL
  (`/app/signed-up`, `/app/business-created`, `/app/first-quote-sent`) plus the visitor's
  browser and IP, which Plausible uses for a daily rotating hash and doesn't keep.
- No client data, user ids, business ids, emails or names are ever sent;
  `test/integration/marketing/analytics_test.rb` checks the script placement and event payloads.
