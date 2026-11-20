# Operations runbook

How Shadetree runs in staging and production: set up, deploy, roll back, back up, restore, and
rotate secrets. It follows the owner's fleet-cmdb deployment ([ADR 0023](../adr/0023-homelab-vms-and-cloudflare-tunnel.md));
spec [PLT-09](../specs/platform/PLT-09-environments-deploy.md).

```
 Visitor ──HTTPS──> Cloudflare ──tunnel──> cloudflared (op-works) ──HTTPS, Origin CA cert──> VM:443
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
| VM, container | `stg-shadetree-vm.hostilecity.net`, `shadetree-staging` | `shadetree-vm.hostilecity.net`, `shadetree-production` |
| Databases | `shadetree_staging` (+ `_cache`, `_queue`, `_cable`) | `shadetree_production` (+ the same three) |
| Uploads | volume `shadetree-staging_storage` | volume `shadetree-production_storage` |
| Email | **Sandbox** (forced by the deploy): only `MAIL_ALLOWLIST` receives mail, copies go to `MAIL_SANDBOX_TO` | Real delivery |
| Third parties | Test mode only: the deploy refuses live Stripe keys | Live keys |
| Data | Reference data the app seeds itself, plus accounts you sign up; never production data | Real |
| Backups | Same as production (the mount may be local: `BACKUP_ALLOW_LOCAL=true`) | Nightly, off-machine |

## One-time setup

### In op-works (per VM)

| What | Check |
| --- | --- |
| Linux with Docker; port 443 free | `docker version`; `ss -ltn 'sport = :443'` prints only the header |
| The deploy user `engineer` in the `docker` group (equivalent to root on the VM), with the runner's SSH key | from the runner: `ssh engineer@<vm> docker ps` |
| Lingering for the deploy user, so its backup timer runs without a login: `loginctl enable-linger engineer` | `loginctl show-user engineer -p Linger` prints `Linger=yes` |
| The PostgreSQL container (17), on a Docker network (`DB_NETWORK`), reachable there as `postgres` (or `DB_HOST`) | `docker run --rm --network postgres_postgres_net postgres:17 pg_isready -h postgres` |
| The role `shadetree`, `LOGIN CREATEDB` (the restore drill creates scratch databases), owning `shadetree_<env>`, `shadetree_<env>_cache`, `_queue` and `_cable` | `psql -U postgres -Atc "SELECT rolcreatedb FROM pg_roles WHERE rolname = 'shadetree'"` prints `t` |
| An off-machine backup location mounted at `/var/backups/shadetree-<env>` (or `BACKUP_DIR`), owned by uid 1000, mode 0700 (uid 1000 is the app's user in its containers) | `mountpoint /var/backups/shadetree-production` |
| A firewall rule: the app's port only from the tunnel connector, and 22 from the runner (below) | from another LAN host, `curl -k https://<vm>/up` times out |
| Swap, on a small VM (below) | `swapon --show` |

In op-works (Ansible, `remote_user: engineer`): add both VMs to the inventory
(`shadetree-vm.hostilecity.net` for production, `stg-shadetree-vm.hostilecity.net` for staging)
and to the playbook's `hosts:` line, and give each its database settings in host vars (the two
need different names and passwords), for example
`host_vars/shadetree-vm.hostilecity.net.yml`:

```yaml
postgres_app_user: shadetree
postgres_app_password: "{{ lookup('env', 'SHADETREE_PRODUCTION_DB_PASSWORD') }}"
postgres_app_databases: [shadetree_production, shadetree_production_cache, shadetree_production_queue, shadetree_production_cable]
```

and the same for staging with `shadetree_staging…` and its own password. The playbook's
`createuser` doesn't grant `CREATEDB`; run once per VM:
`docker exec postgres psql -U postgres -c 'ALTER ROLE shadetree CREATEDB;'`. Then, as root:
`loginctl enable-linger engineer` and `install -d -m 0700 -o 1000 -g 1000 /var/backups/shadetree-<env>`
(before mounting the backup location there).

The database needs no published port: the app and the backups reach it on its Docker network. If
the deploy user joined `docker` after lingering started its systemd instance, restart it once:
`systemctl restart user@$(id -u engineer).service`.

**Firewall.** `ufw` and similar don't see Docker's published ports: Docker's own NAT rules forward
them first. Filter in the `DOCKER-USER` chain, which Docker leaves to you and runs first. After
NAT the destination is the container's port, 3443. With `192.0.2.20` standing for the tunnel
connector and `ens192` for the VM's LAN interface:

```sh
iptables -I DOCKER-USER -i ens192 -p tcp --dport 3443 ! -s 192.0.2.20 -j DROP
```

Docker recreates the chain when it starts, so keep the rule with a unit that runs after Docker
(an `iptables-persistent` save would also restore Docker's own rules and fight it), e.g.
`/etc/systemd/system/shadetree-firewall.service`:

```ini
[Unit]
Description=Only the tunnel connector reaches Shadetree's HTTPS port
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'iptables -C DOCKER-USER -i ens192 -p tcp --dport 3443 ! -s 192.0.2.20 -j DROP 2>/dev/null || iptables -I DOCKER-USER -i ens192 -p tcp --dport 3443 ! -s 192.0.2.20 -j DROP'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

`systemctl enable --now shadetree-firewall`. Both belong in op-works' Ansible.

**VM size.** The VMs are small (1 vCPU, 2 GB RAM, 20 GB disk). That runs staging, but production
is better at **4 GB**: the app (Puma, Solid Queue and, for PDFs, Chrome) is capped at `APP_MEMORY`
(1 GB) next to PostgreSQL, and a build on the VM needs headroom. Add swap on each VM, which keeps a
build or a PDF spike from the out-of-memory killer:

```sh
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

The deploy and the backup check free disk first (`MIN_FREE_MB`, 3 GB; `BACKUP_MIN_FREE_MB`,
1 GB) and stop with a message rather than fill it. Each deploy keeps the last three images and
prunes build cache older than a week; `docker system df` shows what's used.

### Cloudflare

1. **Origin certificate**, per VM: SSL/TLS → Origin Server → Create Certificate, key type ECC,
   hostnames: **only** the VM's internal hostname (`ORIGIN_HOST`). Copy the certificate into the
   secret `TLS_CERT` and the key into `TLS_KEY` (shown once).
2. **Tunnel public hostnames** (op-works):
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
  repository level, default labels `self-hosted`, `Linux`, `X64`) on a LAN machine. It needs
  `bash`, `ssh`, `tar` and `openssl` (`git` is optional).
- Make it **ephemeral**: one job per registration, so nothing a job leaves behind reaches the
  next. Either `./config.sh --url https://github.com/ryaan-anthony/shadetree --token <token>
  --ephemeral` re-registered by a wrapper after each job, or a just-in-time runner
  (`POST /repos/ryaan-anthony/shadetree/actions/runners/generate-jitconfig`, then
  `./run.sh --jitconfig <config>`), started fresh, ideally in a throwaway container or VM.
- **Limit its egress** to what a deploy needs: port 22 on the two VMs, and HTTPS to GitHub
  (`github.com`, `api.github.com`, `*.actions.githubusercontent.com`,
  `codeload.github.com`, `objects.githubusercontent.com`) for the job itself. Nothing else on the LAN.
- **Fork safety:** a self-hosted runner must never run code from a fork's pull request. The
  Deploy workflow has no `pull_request` trigger: it runs only after CI and Deploy CI pass on a push
  to `main` of this repository, on tags and by hand. CI and Deploy CI run on GitHub's runners, and
  Deploy CI fails if any workflow a pull request triggers uses a self-hosted runner
  (`script/ci/check_self_hosted`). Keep Settings → Actions → "Require approval for all external
  contributors", and **never approve a fork pull request's workflow run that touches
  `.github/`**: it could add a job for the self-hosted runner.

### Before the first production deploy (required)

A tag push runs `deploy.yml` **from the tagged commit**, so whoever can push a `v*` tag could tag
a commit whose workflow skips the gate and reach the production secrets. The gate in the workflow
is only defence in depth; these settings are what protect production. **Don't create the
`production` environment's secrets until all three are in place.**

1. **A tag ruleset**: Settings → Rules → Rulesets → New ruleset → **New tag ruleset**. Name
   `release tags`, Enforcement status **Active**. Bypass list: add **Repository admin** (you).
   Target tags → Add target → **Include by pattern** `v*`. Rules: tick **Restrict creations**,
   **Restrict updates** and **Restrict deletions**. Create. Only you can then create, move or
   delete a `v*` tag.
2. **A required reviewer on `production`**: Settings → Environments → `production` → tick
   **Required reviewers**, add yourself (and tick **Prevent self-review** only if someone else
   reviews). Every production deploy then waits for your approval in the run.
3. **The deployment rule**: in the same environment, Deployment branches and tags → **Selected
   branches and tags** → Add rule → Ref type **Tag**, pattern `v*` (and no branch). A run from any
   other ref can't use the environment's secrets.

### GitHub: environments

Settings → Environments: **`staging`** (deployment branches: `main` only) and **`production`**
(set up as in the section above: tags `v*` only, with a required reviewer). Then set, in each:

| Name | Kind | Staging | Production | What it is |
| --- | --- | --- | --- | --- |
| `DEPLOY_HOST` | var | `stg-shadetree-vm.hostilecity.net` | `shadetree-vm.hostilecity.net` | The VM, as the runner reaches it |
| `DEPLOY_USER` | var | `engineer` | `engineer` | The deploy user |
| `DEPLOY_KNOWN_HOSTS` | var | `ssh-keyscan -H` lines, checked | same, **required** | The VM's SSH host keys. Unset on staging: each deploy trusts the key the VM presents (warned) |
| `DEPLOY_DIR` | var, optional | `shadetree` | `shadetree` | Working directory under the deploy user's home |
| `SSH_PRIVATE_KEY` | secret | | | The runner's key for the deploy user |
| `ORIGIN_HOST` | var, optional | (`DEPLOY_HOST`) | (`DEPLOY_HOST`) | The tunnel's origin; the certificate must cover it. Default `DEPLOY_HOST` |
| `PUBLISH_PORT` | var, optional | `443` | `443` | The VM port the tunnel connects to |
| `TLS_CERT`, `TLS_KEY` | secrets | | | The Origin CA certificate and key, PEM. The deploy checks it's signed by Cloudflare's Origin CA (`ops/tls/`) |
| `APP_HOST` | var | `staging.getshadetree.com` | `getshadetree.com` | Host for host authorization and links in email |
| `TRUSTED_PROXIES` | var | connector address | connector address | Comma-separated IPs or CIDRs allowed to set `X-Forwarded-For`; none broader than /24 (IPv4) or /64 (IPv6) |
| `DB_NETWORK` | var | `postgres_postgres_net` | `postgres_postgres_net` | The PostgreSQL container's Docker network (op-works: compose project `postgres`, network `postgres_net`) |
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
| `STRIPE_CONNECT_CLIENT_ID` | var | test-mode client id | live client id | Stripe Connect onboarding (PAY-03) |
| `INBOUND_EMAIL_SECRET` | secret | | | Signs inbound support email (OPS-05) |
| `INBOUND_EMAIL_ENABLED` | var, optional | | | `true` turns inbound support email on (OPS-05) |
| `STRIPE_AUTOMATIC_TAX` | var, optional | `true` (default) | `true` | `false` turns Stripe Tax off on subscriptions (needs Stripe Tax enabled in the account) |
| `TRIAL_DAYS` | var, optional | `14` (default) | `14` | Length of a new business's paid-plan trial; `0` turns trials off (BIL-05) |
| `TRIAL_PLAN` | var, optional | `pro` (default) | `pro` | The plan the trial is of |
| `BILLING_GRACE_DAYS` | var, optional | `7` (default) | `7` | Days a failed subscription payment is tolerated |
| `ANALYTICS_HOST`, `ANALYTICS_DOMAIN` | vars, optional | unset | Plausible's host, `getshadetree.com` | MKT-04; unset sends nothing |
| `STRUCTURED_LOGS` | var, optional | `true` (default) | `true` | JSON log lines (PLT-10) |
| `SLOW_REQUEST_MS`, `SLOW_QUERY_MS` | vars, optional | `1000`, `250` | same | PLT-10 thresholds |
| `JOB_BACKLOG_THRESHOLD`, `JOB_WAIT_THRESHOLD` | vars, optional | `100`, `600` | same | PLT-10 job alerts and `/up/jobs` |
| `JOB_CONCURRENCY` | var, optional | `1` | `1` | Solid Queue worker processes |
| `APP_MEMORY` | var, optional | `1g` | `1g` (`1536m` on a 4 GB VM) | The container's memory limit |
| `MIN_FREE_MB` | var, optional | `3072` | `3072` | Free disk a deploy needs |
| `RAILS_LOG_LEVEL` | var, optional | `info` | `info` | |
| `BACKUP_DIR` | var, optional | `/var/backups/shadetree-staging` | `/var/backups/shadetree-production` | The backup mount |
| `BACKUP_ALLOW_LOCAL` | var, optional | `true` if not mounted | `false` | Accept sets on the VM's own disk |
| `BACKUP_RETENTION_DAYS` | var, optional | `7` | `30` | Daily sets kept |
| `BACKUP_KEEP_MONTHLY` | var, optional | `false` | `true` | Also keep the oldest set of each month for a year |
| `BACKUP_DRILL_HOST` | var, optional | | | Another PostgreSQL on `DB_NETWORK` for the drill's scratch databases, once the database outgrows the VM's disk |
| `BACKUP_MIN_FREE_MB` | var, optional | `1024` | `1024` | Free disk a backup or drill needs |
| `BACKUP_PG_IMAGE` | var, optional | `postgres:17` | `postgres:17` | Must be the server's major version or newer; may be pinned by digest |
| `BACKUP_MAX_AGE_HOURS` | var, optional | `26` | `26` | When `/up/backup` turns 503 |
| `EXTRA_SETTINGS` | var, optional | | | Any other non-secret setting, `NAME=value` per line (e.g. `FORMS_LOCKDOWN=true`). It can't set anything above, nor `STRIPE_*`, `PG*`, `DATABASE_*`, `TLS_*`, `SMTP_*`, `MAIL_*`, `INBOUND_EMAIL_*` or `SECRET_KEY_BASE` |

The deploy stops with a message when a required value is missing or malformed, when a value that
must be secret is set as a variable, when staging has a live Stripe key (production with test keys
only warns), when `TRUSTED_PROXIES` is too broad, or when the certificate isn't Cloudflare's,
doesn't cover `ORIGIN_HOST`, doesn't match its key or has expired; in each case before anything
is shipped. Only names are printed, never values. Secrets reach the VM on SSH standard input, into a
mode-0600 env file for `docker run --env-file`, deleted once the container has started; Docker
keeps them in the container's configuration, readable only by the `docker` group.

## Deploy

- **Staging:** merge to `main`. When CI and Deploy CI have both passed, Actions → Deploy runs
  (started by whichever finishes second). Only `main`'s newest commit deploys: a run for an older
  one does nothing. By hand: Run workflow on `main`.
- **Production:** once CI and Deploy CI have passed on `main` for the commit, tag it:
  `git tag v1.4.0 <sha> && git push origin v1.4.0`, then approve the run. By hand: Run workflow,
  "Use workflow from" the tag. A tag on a commit that isn't on `main`, or whose checks haven't
  passed, is refused.
- What `ops/deploy/deploy.sh` does on the VM, in order: waits for a running backup; checks free
  disk; builds the image (or reuses it, if this commit was built before); runs a **pre-flight** in
  a one-off container (the app boots with the new settings and reaches the database) and then the
  **migrations**, both while the old release keeps serving; then stops the old container, keeps it
  aside, and starts the new one. If the new one doesn't answer `/up` and HTTPS within two minutes,
  the old one is started again. Every failure says whether **the site is UP or DOWN** and what to
  do next. The old container's log is saved to `~/.local/state/shadetree-<env>/logs/` (last five).
- **Downtime:** a deploy isn't zero-downtime. Between the old container stopping and the new one
  answering, visitors get about **30–90 seconds of 502s** from Cloudflare. Deploy production when
  it's quiet.
- Migrations run before the swap, so the old release briefly runs against the new schema. Keep
  them backward-compatible with the previous release (add, backfill, then remove in a later
  release); rollback relies on the same rule.
- A deploy waits up to 20 minutes for a running backup or drill, and refuses during a restore.
- The container runs as uid 1000 with a read-only file system, no capabilities, `APP_MEMORY`
  of memory and a capped log (10 MB × 5).

## Roll back

- **Production:** re-run the Deploy run of the last good tag (Actions → Deploy → the run → Re-run
  all jobs). The VM keeps the last three images, so there's no build. GitHub only re-runs runs
  from the last **30 days**; for an older release, push a new tag on that commit
  (`git tag v1.4.1 <good sha>`), which rebuilds it.
- **Staging:** revert on `main`. Staging always runs `main`'s newest commit.
- **By hand, on the VM**, when GitHub isn't available: `docker images shadetree-production` lists
  the kept images (tagged with their commit). Run one with the current container's settings:

  ```sh
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' shadetree-production > /tmp/st.env  # mode 0600, delete after
  docker stop shadetree-production && docker rename shadetree-production shadetree-production-old
  docker run -d --name shadetree-production -p 443:3443 --network postgres_postgres_net --restart unless-stopped \
    --cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp --tmpfs /rails/tmp:uid=1000,gid=1000 \
    --tmpfs /rails/log:uid=1000,gid=1000 --tmpfs /home/rails:uid=1000,gid=1000 --memory 1g \
    -v shadetree-production_storage:/rails/storage --env-file /tmp/st.env shadetree-production:<sha>
  rm /tmp/st.env   # then, once it answers: docker rm shadetree-production-old
  ```

  Its `APP_REVISION` still names the newer commit until the next deploy.
- A rollback doesn't undo migrations: restore (below) or write a follow-up migration.

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

Retention: sets older than `BACKUP_RETENTION_DAYS` (production 30, staging 7) are pruned, except,
with `BACKUP_KEEP_MONTHLY` (production's default), the oldest set of each month, kept for a year;
the newest three always stay. The drill prints the scratch databases' size first; it needs that
much free space on the PostgreSQL server (`BACKUP_DRILL_HOST` moves it to another one). No secret is stored for backups: the
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
2. In op-works, bring back the VM, PostgreSQL (role and four empty databases) and the backup
   mount. Then enable the workflow and re-run the last production deploy: the app comes up empty.
   Its nightly backup refuses the empty database, so the good sets stay newest.
3. On the VM: `docker stop shadetree-production`, then drop the two databases the restore
   fills: `docker exec postgres dropdb -U postgres shadetree_production` and
   `docker exec postgres dropdb -U postgres shadetree_production_queue`.
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

## Decisions for the owner

Not built; each is your call:

- **Point-in-time recovery.** Backups are nightly, so up to a day of data can be lost. WAL
  archiving (for example with pgBackRest or WAL-G) would bring that to minutes, at the cost of
  more storage and another moving part.
- **Encrypting off-machine backups.** Sets are written in the clear to the backup mount. Piping
  each file through [age](https://age-encryption.org) to a public key (the private key kept
  offline) would protect them if the backup location leaks; restores then need the key.

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
