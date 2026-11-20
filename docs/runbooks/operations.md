# Operations runbook

How Shadetree runs in staging and production: set up, deploy, roll back, back up, restore, and
rotate secrets. It follows the owner's fleet-cmdb deployment ([ADR 0023](../adr/0023-homelab-vms-and-cloudflare-tunnel.md));
spec [PLT-09](../specs/platform/PLT-09-environments-deploy.md).

```
 Visitor ──HTTPS──> Cloudflare ──tunnel──> cloudflared (ops-work) ──HTTPS, Origin CA cert──> VM:443
                                                                                            │
 GitHub ──> self-hosted runner (LAN) ──SSH: code, env file──> VM      shadetree-<env> container (:3443)
                                                                     │ Docker network     │ volume
                                                                     postgres container   shadetree-<env>_storage
```

Each environment is one VM with Docker. The Deploy workflow (`.github/workflows/deploy.yml`) runs
on a self-hosted runner on the LAN: it ships the commit to the VM over SSH, builds the image there
and replaces the container `shadetree-<env>`, which joins the PostgreSQL container's Docker
network. Background jobs and recurring tasks run inside Puma (Solid Queue). Every night a systemd
timer of the deploy user backs up the databases and uploads, then restore-drills that backup.

## Environments

| | Staging | Production |
| --- | --- | --- |
| Deploys | Every push to `main`, once CI has passed on it | A pushed tag `vX.Y.Z` on a commit of `main` whose CI passed |
| Public hostname (`APP_HOST`) | `staging.getshadetree.com` | `getshadetree.com` |
| VM, container | the staging VM, `shadetree-staging` | the production VM, `shadetree-production` |
| Databases | `shadetree_staging` (+ `_cache`, `_queue`, `_cable`) | `shadetree_production` (+ the same three) |
| Uploads | volume `shadetree-staging_storage` | volume `shadetree-production_storage` |
| Email | **Sandbox** (forced by the deploy): only `MAIL_ALLOWLIST` receives mail, copies go to `MAIL_SANDBOX_TO` | Real delivery |
| Third parties | Test mode only: the deploy refuses live Stripe keys | Live keys |
| Data | Reference data the app seeds itself, plus accounts you sign up; never production data | Real |
| Backups | Same as production (the mount may be local: `BACKUP_ALLOW_LOCAL=true`) | Nightly, off-machine |

## One-time setup

### In ops-work (per VM)

| What | Check |
| --- | --- |
| Linux with Docker; port 443 free | `docker version`; `ss -ltn 'sport = :443'` prints only the header |
| A deploy user (`deploy` below) in the `docker` group (equivalent to root on the VM), with the runner's SSH key | from the runner: `ssh deploy@<vm> docker ps` |
| Lingering for the deploy user, so its backup timer runs without a login: `loginctl enable-linger deploy` | `loginctl show-user deploy -p Linger` prints `Linger=yes` |
| The PostgreSQL container (17), on a Docker network (`DB_NETWORK`), reachable there as `postgres` (or `DB_HOST`) | `docker run --rm --network <net> postgres:17 pg_isready -h postgres` |
| The role `shadetree`, `LOGIN CREATEDB` (the restore drill creates scratch databases), owning `shadetree_<env>`, `shadetree_<env>_cache`, `_queue` and `_cable` | `psql -U postgres -Atc "SELECT rolcreatedb FROM pg_roles WHERE rolname = 'shadetree'"` prints `t` |
| An off-machine backup location mounted at `/var/backups/shadetree-<env>` (or `BACKUP_DIR`), owned by uid 1000, mode 0700 (uid 1000 is the app's user in its containers) | `mountpoint /var/backups/shadetree-production` |
| A firewall rule: port 443 only from the tunnel connector (and the runner needs port 22) | |

The database needs no published port: the app and the backups reach it on its Docker network. If
the deploy user joined `docker` after lingering started its systemd instance, restart it once:
`systemctl restart user@$(id -u deploy).service`.

### Cloudflare

1. **Origin certificate**, per VM: SSL/TLS → Origin Server → Create Certificate, key type ECC,
   hostnames: **only** the VM's internal hostname (`ORIGIN_HOST`). Copy the certificate into the
   secret `TLS_CERT` and the key into `TLS_KEY` (shown once).
2. **Tunnel public hostnames** (ops-work):
   - `staging.getshadetree.com` → service **HTTPS** `https://<staging VM internal hostname>:443`
   - `getshadetree.com` → service **HTTPS** `https://<production VM internal hostname>:443`
   - Leave **No TLS Verify** off, **Origin Server Name** empty (the URL's hostname) and **HTTP
     Host Header** empty, so the app sees the public hostname. `www.getshadetree.com` is a
     Cloudflare redirect rule to the apex, not a tunnel hostname.
   - Never publish the internal hostname itself.
3. Note the tunnel connector's address as the VM sees it: it goes in `TRUSTED_PROXIES`. After the
   first deploy, check the logs' `[abuse]` lines show visitors' addresses, not the connector's.

### GitHub: the runner

- Register a **self-hosted runner for `ryaan-anthony/shadetree`** (Settings → Actions → Runners,
  repository level, default labels `self-hosted`, `Linux`, `X64`) on a LAN machine that reaches
  both VMs on port 22. It needs `bash`, `ssh`, `tar` and `openssl` (`git` is optional).
- **Fork safety:** a self-hosted runner must never run code from a fork's pull request. The
  Deploy workflow has no `pull_request` trigger: it runs only after CI passes on a push to `main`
  of this repository, on tags and by hand. Deploy CI and CI run on GitHub's runners. Keep it that
  way (no `runs-on: self-hosted` in any workflow a pull request triggers), and keep Settings →
  Actions → "Require approval for all external contributors".

### GitHub: environments

Settings → Environments: **`staging`** (deployment branches: `main` only) and **`production`**
(deployment tags: `v*` only). Optionally add a required reviewer to `production`, so every tag
waits for your approval. Then set, in each:

| Name | Kind | Staging | Production | What it is |
| --- | --- | --- | --- | --- |
| `DEPLOY_HOST` | var | staging VM | production VM | The VM, as the runner reaches it |
| `DEPLOY_USER` | var | `deploy` | `deploy` | The deploy user |
| `DEPLOY_KNOWN_HOSTS` | var, recommended | `ssh-keyscan -H` lines, checked | same | Unset: each deploy trusts the key the VM presents (warned) |
| `DEPLOY_DIR` | var, optional | `shadetree` | `shadetree` | Working directory under the deploy user's home |
| `SSH_PRIVATE_KEY` | secret | | | The runner's key for the deploy user |
| `ORIGIN_HOST` | var, optional | internal hostname | internal hostname | The tunnel's origin; the certificate must cover it. Default `DEPLOY_HOST` |
| `PUBLISH_PORT` | var, optional | `443` | `443` | The VM port the tunnel connects to |
| `TLS_CERT`, `TLS_KEY` | secrets | | | The Origin CA certificate and key, PEM |
| `APP_HOST` | var | `staging.getshadetree.com` | `getshadetree.com` | Host for host authorization and links in email |
| `TRUSTED_PROXIES` | var | connector address | connector address | Comma-separated IPs or CIDRs allowed to set `X-Forwarded-For` |
| `DB_NETWORK` | var | | | The PostgreSQL container's Docker network |
| `DB_HOST` | var, optional | `postgres` | `postgres` | The PostgreSQL container's name on it |
| `DB_NAME` | var, optional | `shadetree_staging` | `shadetree_production` | The primary database; the others add `_cache`, `_queue`, `_cable` |
| `DB_USER` | var, optional | `shadetree` | `shadetree` | |
| `DATABASE_PASSWORD` | secret | | | The role's password |
| `SECRET_KEY_BASE` | secret | `openssl rand -hex 64` | another one | Signs sessions and derives client-link tokens (ADR 0016) |
| `MAIL_FROM` | var | `Shadetree <no-reply@getshadetree.com>` | same | The platform sender |
| `SMTP_ADDRESS`, `SMTP_PORT` | vars | the provider's **sandbox** relay | its relay | Port default 587 (STARTTLS); nothing is sent without an address |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | secrets | sandbox credentials | live credentials | |
| `MAIL_ALLOWLIST` | var, staging | `you@example.com,@getshadetree.com` | | Addresses or `@domains` staging may email |
| `MAIL_SANDBOX_TO` | var, staging | a shared test inbox | | Gets a copy of anything blocked |
| `SUPPORT_EMAIL` | var, optional | | | Where contact-form mail goes |
| `STRIPE_SECRET_KEY` | secret | `sk_test_…` (enforced) | `sk_live_…` | Payments (PAY, BIL specs) |
| `STRIPE_PUBLISHABLE_KEY` | var | `pk_test_…` (enforced) | `pk_live_…` | |
| `STRIPE_WEBHOOK_SECRET`, `STRIPE_CONNECT_WEBHOOK_SECRET` | secrets | test-mode endpoints' | live endpoints' | Signing secrets of the two webhook endpoints |
| `INBOUND_EMAIL_SECRET` | secret | | | Signs inbound support email (OPS-05) |
| `ANALYTICS_HOST`, `ANALYTICS_DOMAIN` | vars, optional | unset | Plausible's host, `getshadetree.com` | MKT-04; unset sends nothing |
| `STRUCTURED_LOGS` | var, optional | `true` (default) | `true` | JSON log lines (PLT-10) |
| `SLOW_REQUEST_MS`, `SLOW_QUERY_MS` | vars, optional | `1000`, `250` | same | PLT-10 thresholds |
| `JOB_BACKLOG_THRESHOLD`, `JOB_WAIT_THRESHOLD` | vars, optional | `100`, `600` | same | PLT-10 job alerts and `/up/jobs` |
| `JOB_CONCURRENCY` | var, optional | `1` | `1` | Solid Queue worker processes |
| `RAILS_LOG_LEVEL` | var, optional | `info` | `info` | |
| `BACKUP_DIR` | var, optional | `/var/backups/shadetree-staging` | `/var/backups/shadetree-production` | The backup mount |
| `BACKUP_ALLOW_LOCAL` | var, optional | `true` if not mounted | `false` | Accept sets on the VM's own disk |
| `BACKUP_RETENTION_DAYS` | var, optional | `30` | `30` | Daily sets kept; plus the oldest of each month for a year |
| `BACKUP_PG_IMAGE` | var, optional | `postgres:17` | `postgres:17` | Must be the server's major version or newer; may be pinned by digest |
| `BACKUP_MAX_AGE_HOURS` | var, optional | `26` | `26` | When `/up/backup` turns 503 |
| `EXTRA_SETTINGS` | var, optional | | | Any other non-secret setting, `NAME=value` per line (e.g. `FORMS_LOCKDOWN=true`) |

The deploy stops with a message when a required value is missing or malformed, when a value that
must be secret is set as a variable, when staging has a live Stripe key, or when the certificate
doesn't cover `ORIGIN_HOST`, doesn't match its key or has expired; in each case before the app is
replaced. Only names are printed, never values. Secrets reach the VM on SSH standard input, into a
mode-0600 env file for `docker run --env-file`, deleted once the container has started; Docker
keeps them in the container's configuration, readable only by the `docker` group.

## Deploy

- **Staging:** merge to `main`. When CI passes, Actions → Deploy runs. By hand: Run workflow on `main`.
- **Production:** once CI has passed on `main` for the commit, tag it: `git tag v1.4.0 <sha> &&
  git push origin v1.4.0`. By hand: Run workflow, "Use workflow from" the tag. A tag on a commit
  that isn't on `main`, or whose CI hasn't passed, is refused.
- The log shows the commit, the backup timer's next run, the build, `wait for /up` (the first
  start creates and migrates the databases), the container, `/up/jobs` and `/up/backup`.
- Migrations run on boot. Keep them backward-compatible with the previous release so rollback
  stays safe: add, backfill, then remove in a later release.
- A deploy waits up to 20 minutes for a running backup or drill, and refuses during a restore.

## Roll back

Re-run an earlier, good Deploy run for that environment (Actions → Deploy → the run → Re-run
jobs): it redeploys its own commit. For production, or tag the good commit with a new version. A
rollback doesn't undo migrations: restore (below) or write a follow-up migration.

## Backups

Every night (07:30 UTC, caught up after a missed run) the timer `shadetree-backup@<env>.timer`
runs `docker.sh <env> nightly`:

1. **Backup:** one set `shadetree-<env>-<UTC time>/` in `BACKUP_DIR`: `primary.dump` and
   `queue.dump` (`pg_dump`, in a throwaway `postgres` container on the database network),
   `storage.tar` (the uploads in the volume), `counts` and `SHA256SUMS`. The cache and cable
   databases are short-lived data; the app recreates their tables. A database with no business
   where the newest set had some (a rebuilt server's empty database) is refused, so it can't
   become the newest set and push the good ones out.
2. **Restore drill:** the new set is restored into scratch databases and a scratch volume, and the
   app's own image checks it (`bin/rails backup:verify_restore`: schema, at least the counted
   users, businesses, clients and uploads, and the newest 200 files with their sizes). Nothing
   live is touched; the scratch copies are dropped.
3. `/up/backup` answers `ok`, `stale` (no backup in 26 hours) or `untested` (no passing drill
   since). Point the uptime check at it.

Retention: sets older than `BACKUP_RETENTION_DAYS` (30) are pruned, except the oldest set of each
month, kept for a year; the newest three always stay. No secret is stored for backups: the
database settings are read from the app container when the backup runs. The sets hold every
business's data: restrict the backup location to uid 1000 and encrypt it at rest. Keep the
environments' secrets (above) in a password manager, never with the sets.

On the VM, as the deploy user (`B=~/.local/share/shadetree-production/backup/docker.sh`):

```sh
systemctl --user list-timers 'shadetree-backup@*'          # the next run
journalctl --user -u shadetree-backup@production -n 50      # the last runs (or as root: _SYSTEMD_USER_UNIT=…)
$B production backup                                        # a backup now
$B production restore-drill                                 # drill the newest set (or name one)
$B production list                                          # sets, sizes, counts
$B production delete shadetree-production-20261120T073112Z  # one set by hand (never the newest)
```

Backup, drill, restore and deploy share one lock; Deploy CI exercises all of them on every PR
that changes the app.

## Restore

To recover a lost server or database (production shown; staging is the same with its names):

1. **Pause deploys:** Actions → Deploy → Disable workflow.
2. In ops-work, bring back the VM, PostgreSQL (role and four empty databases) and the backup
   mount. Then enable the workflow and re-run the last production deploy: the app comes up empty.
   Its nightly backup refuses the empty database, so the good sets stay newest.
3. On the VM: `docker stop shadetree-production`, then drop the two databases the restore
   fills: `docker exec <postgres> dropdb -U postgres shadetree_production` and
   `… shadetree_production_queue`.
4. `$B production list`, then `$B production restore shadetree-production-<time>`. It refuses a
   running app, databases that hold data, a non-empty volume and a damaged set, before changing
   anything. A restore that fails part-way leaves a marker that makes backups and deploys refuse;
   its text says what to drop before trying again.
5. `docker start shadetree-production`, check sign-in and a client link, and
   `$B production restore-drill` (or wait for the night): `/up/backup` is `untested` until then.
6. Record it below.

### Restore log

| Date | Environment | Set | Result | Notes |
| --- | --- | --- | --- | --- |
| *(pending)* | staging, then production | first nightly set | | First manual restore once the VMs exist (PLT-09 acceptance) |

## Rotate a secret

1. Create the new value without revoking the old one.
2. Update it in the GitHub environment.
3. Re-run the environment's last Deploy run (or Run workflow on `main` / the tag).
4. Revoke the old value; check `/up`, sign-in and, on staging, a test email.

Special cases:

- **`SECRET_KEY_BASE`:** rotating it signs everyone out and invalidates every **client link** and
  invitation link, since their tokens are derived from it (ADR 0016). Re-issue open links
  afterwards; there's no bulk tool yet, so do it only for a leak, as an incident.
- **`DATABASE_PASSWORD`:** `ALTER ROLE shadetree PASSWORD '…'` in PostgreSQL, update the secret,
  redeploy at once (the old password stops working immediately).
- **`TLS_CERT`/`TLS_KEY`:** issue a new Origin certificate, update both secrets, redeploy, then
  revoke the old one. The deploy warns 30 days before expiry; Cloudflare sends no reminder.
- **`SSH_PRIVATE_KEY`:** add the new public key to the deploy user's `authorized_keys`, update the
  secret, deploy, then remove the old key.
- **Stripe, SMTP and inbound-email secrets:** roll them in the provider's dashboard (Stripe can
  keep the old webhook secret valid for a while), update, redeploy.

## Monthly cost

Pre-revenue target: under **$50/month** (vision constraint). Update this table when anything
changes.

| Item | Monthly |
| --- | --- |
| Hosting: the owner's homelab VMs, PostgreSQL, backup storage, runner | $0 (owner's hardware and power) |
| Cloudflare: DNS, tunnel, Origin CA certificates (free plan) | $0 |
| Domain `getshadetree.com` (annual ÷ 12) | *tbd* (about $1) |
| Email: the SMTP provider (staging sandbox, production sending) | *tbd* |
| Stripe | $0 fixed; per-transaction fees |
| Analytics: self-hosted Plausible (MKT-04) | $0 if on the homelab |
| GitHub (public repository, Actions) | $0 |
| **Total** | **target < $50** |
