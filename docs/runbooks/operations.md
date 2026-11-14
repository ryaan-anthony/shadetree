# Operations runbook

How Shadetree runs in staging and production: deploy, roll back, back up, restore, and rotate
secrets. Decisions: [ADR 0009](../adr/0009-hosting-kamal-vps.md) (hosting),
[ADR 0002](../adr/0002-postgresql.md) (database), [ADR 0008](../adr/0008-active-storage-object-storage.md)
(files). Spec: [PLT-09](../specs/platform/PLT-09-environments-deploy.md).

## Environments

| | Staging | Production |
| --- | --- | --- |
| Deploys | Automatically after CI passes on `main` | When a GitHub release is published, or by hand |
| Host | One small VPS (`STAGING_HOST`) | One VPS (`PRODUCTION_HOST`) |
| Domain and TLS | `STAGING_DOMAIN`, Let's Encrypt through kamal-proxy | `PRODUCTION_DOMAIN`, same |
| Database | Managed PostgreSQL: four databases (primary, cache, queue, cable) | Same, on its own server |
| Files | Its own bucket | Its own bucket, copied nightly to the backup bucket |
| Email | **Sandbox:** only `STAGING_MAIL_ALLOWLIST` receives mail; the rest goes to `STAGING_MAIL_SANDBOX_TO` | Real delivery |
| Third parties | Test-mode keys only (Stripe test mode, Postmark sandbox server) | Live keys |
| Jobs and schedules | Solid Queue inside Puma, including `config/recurring.yml` | Same |
| Data | Seeded demo data only (`bin/rails db:seed`), never production data | Real |

Configuration lives in GitHub **environments** (Settings → Environments → `staging` /
`production`). Values marked *var* are variables; the rest are secrets.

| Name | Used for |
| --- | --- |
| `STAGING_HOST` / `PRODUCTION_HOST` *var* | Server IP or hostname |
| `STAGING_DOMAIN` / `PRODUCTION_DOMAIN` *var* | Public domain; DNS A record points at the host |
| `SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS` *var* | Deploy key for the host (root or a `docker` group user) |
| `RAILS_MASTER_KEY` | Decrypts `config/credentials.yml.enc` |
| `DATABASE_URL`, `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, `CABLE_DATABASE_URL` | Managed PostgreSQL, one database each |
| `STORAGE_ENDPOINT`, `STORAGE_BUCKET` *vars*; `STORAGE_ACCESS_KEY_ID`, `STORAGE_SECRET_ACCESS_KEY` | Object storage |
| `SMTP_USERNAME`, `SMTP_PASSWORD`; `MAIL_FROM` *var* | Outgoing mail (Postmark SMTP token for both) |
| `STAGING_MAIL_ALLOWLIST`, `STAGING_MAIL_SANDBOX_TO` *vars* (staging) | Comma-separated addresses or `@domains`; the sandbox inbox |
| `BACKUP_ENDPOINT`, `BACKUP_BUCKET` *vars*; `BACKUP_ACCESS_KEY_ID`, `BACKUP_SECRET_ACCESS_KEY` (production) | Backup bucket, with credentials separate from the app's |

Protect the `production` environment with a required reviewer, so a release can't deploy
unapproved.

## First-time setup

1. Create both VPSs (Ubuntu LTS, 2 GB+), add the deploy SSH key, and point DNS at them.
2. Create the managed PostgreSQL servers. On each, create `shadetree`, `shadetree_cache`,
   `shadetree_queue` and `shadetree_cable`. Turn on daily snapshots and point-in-time recovery.
3. Create the storage buckets (app files per environment, plus a backup bucket in a different
   account or with different credentials). Add a lifecycle rule to the backup bucket that
   expires `db/` objects after 30 days, except the first of each month, which is kept for 12
   months.
4. Fill in the GitHub environment variables and secrets above.
5. From a laptop with the same variables exported: `bin/kamal setup -d staging`, then
   `bin/kamal setup -d production`. After that, everything goes through the Deploy workflow.

## Deploy

- **Staging** happens on its own after every merge to `main` once CI is green. Watch it under
  Actions → Deploy.
- **Production:** publish a GitHub release (tag `vYYYY.MM.DD`) for a commit that's on staging.
  The workflow waits for the environment's reviewer, then promotes the exact image staging
  ran (`--skip-push --version=<sha>`).
- By hand: Actions → Deploy → Run workflow → pick the environment. Locally:
  `bin/kamal deploy -d staging`.
- Migrations run on boot (`bin/docker-entrypoint` runs `db:prepare`). Keep them
  backward-compatible with the previous release so rollback stays safe: add, backfill, then
  remove in a later release.

## Roll back

1. Find the previous good commit SHA (Actions → Deploy history, or `bin/kamal app containers -d production`).
2. Actions → Deploy → Run workflow → environment `production`, `rollback_to` = that SHA. Locally:
   `bin/kamal rollback <sha> -d production`.
3. Kamal keeps the last five releases on the host (`retain_containers`), so this takes seconds.
   A rollback doesn't undo migrations. If one must be reverted, restore (below) or write a
   follow-up migration.

## Backups

- **Database:** two layers.
  - The managed provider's daily snapshots plus point-in-time recovery. Retention is whatever
    the plan allows, usually 7 days.
  - Our own nightly `pg_dump` of the primary database to the backup bucket (Backup workflow,
    02:23 New York). It's off-provider, kept 30 days plus monthly copies for a year.
  - Cache, queue and cable databases are rebuildable and aren't dumped.
- **Files:** nightly copy of the app bucket to `files/` in the backup bucket (same workflow).
- **Proof:** every Sunday the Backup workflow restores the latest dump into a throwaway
  PostgreSQL and runs `script/ops/verify_restore.rb` (schema current, users and businesses
  present). A failure fails the workflow and GitHub emails the maintainer.

## Restore

For a real incident or a drill into a scratch environment:

1. Pick the point to recover to. For anything under a week, prefer the provider's
   point-in-time restore into a **new** database server. Otherwise download a dump:
   `aws s3 cp s3://$BACKUP_BUCKET/db/primary-<stamp>.dump .`
2. Restore into a new database: `createdb … && pg_restore --no-owner --dbname=… primary-<stamp>.dump`.
3. Check it: `DATABASE_URL=… bin/rails runner script/ops/verify_restore.rb`.
4. Point the environment at it: update `DATABASE_URL` in the GitHub environment, then run the
   Deploy workflow (or `bin/kamal env push -d production && bin/kamal app boot -d production`).
5. Files: `aws s3 sync s3://$BACKUP_BUCKET/files s3://$STORAGE_BUCKET` for anything lost.
6. Write down what happened and what was lost in the restore log below.

### Restore log

| Date | Environment | Source | Result | Notes |
| --- | --- | --- | --- | --- |
| *(pending)* | scratch | first nightly dump | | First drill, once production exists (PLT-09 acceptance) |

## Rotate a secret

1. Create the new value (a new database password, API token or SSH key) without revoking the
   old one.
2. Update it in the GitHub environment.
3. Redeploy: Actions → Deploy → Run workflow (the same version is fine).
4. Revoke the old value, then check the app (`/up`, sign-in, a test email on staging).

Special cases:

- **`RAILS_MASTER_KEY` and `secret_key_base`:** rotating `secret_key_base` signs everyone out
  and invalidates every client link (ADR 0016). Re-issue open links afterwards; there's no tool
  for that yet, so treat it as an incident.
- **SSH deploy key:** add the new public key to the hosts first, update `SSH_PRIVATE_KEY`, then
  remove the old key from `~/.ssh/authorized_keys`.

## Monthly cost

Pre-revenue target: under **$50/month** (vision constraint). Update this table when anything
changes.

| Item | Staging | Production | Monthly |
| --- | --- | --- | --- |
| VPS | *tbd* | *tbd* | |
| Managed PostgreSQL | *tbd* | *tbd* | |
| Object storage and backups | | | |
| Email (Postmark) | | | |
| Domain (annual ÷ 12) | | | |
| **Total** | | | **target < $50** |
