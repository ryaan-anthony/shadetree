# 0023. Staging and production on the owner's homelab VMs, deployed by GitHub Actions, behind a Cloudflare tunnel

- **Status:** Accepted
- **Date:** 2026-11-20
- **Specs:** PLT-09, PLT-10, PLT-13
- **Supersedes in part:** [0002](0002-postgresql.md) (managed PostgreSQL and its provider
  snapshots), [0008](0008-active-storage-object-storage.md) (S3-compatible object storage),
  [0009](0009-hosting-kamal-vps.md) (Kamal on rented VPSs, GitHub Container Registry). The rest
  of each stands: PostgreSQL with four databases, Active Storage with validated, stripped
  images, Solid Queue inside Puma, one server per environment.

## Context

The owner decided (2026-11-20, on PR #134): "I have a homelab that runs my VMs, follow the same
pattern for app deployments as fleet-cmdb. I'll set up the VMs in my op-works repo and have it
provision both staging and production. … For shadetree, I will deploy merges to main to staging
and tagged releases go to production."

fleet-cmdb (the owner's other app) deploys with a GitHub Actions workflow on a self-hosted runner
on the LAN: it ships the commit to the VM over SSH, builds the image there, and runs one
container on the network of a PostgreSQL container that already runs on the VM, with storage in
a Docker volume. Settings come from a GitHub environment and reach the VM only on SSH standard
input. A systemd user timer of the deploy user takes nightly `pg_dump` backups in a throwaway
`postgres` container. The public hostname is published through a Cloudflare tunnel whose origin
is the VM's internal hostname over HTTPS, with a Cloudflare Origin CA certificate the app serves
itself; no forwarded host header is trusted.

## Options considered

1. **Keep #134's plan**: Kamal to rented VPSs, managed PostgreSQL, R2 for files. About $30–60 a
   month, a second deployment pattern for the owner to run, and none of their homelab used.
2. **fleet-cmdb's pattern**, adapted to two environments. Hosting costs nothing extra, the owner
   runs one pattern for both apps, and the VMs, PostgreSQL and tunnel are provisioned in their
   op-works repository.

## Decision

Follow **fleet-cmdb's pattern**, with two GitHub environments and one VM each:

- **Deploys** (`.github/workflows/deploy.yml`, `ops/deploy/deploy.sh`): `staging` after CI
  passes on a push to `main`; `production` on a pushed tag `vX.Y.Z` (or a manual run on one)
  whose commit is on `main` and passed CI. A hosted job checks that, then the self-hosted
  runner deploys. Rollback re-runs an earlier deploy. The container is `shadetree-<environment>`.
- **Database:** the owner's PostgreSQL container on each VM, reached on its Docker network: the
  role `shadetree` (with `CREATEDB`, for the restore drill) owning `shadetree_<environment>` and
  its `_cache`, `_queue` and `_cable` databases.
- **Files:** Active Storage on local disk in the Docker volume `shadetree-<environment>_storage`,
  in every backup. `aws-sdk-s3` is removed.
- **Backups** (`ops/backup/`): nightly, a set of the primary and queue databases and the uploads
  onto an off-machine mount on the VM, then a restore drill of that set into scratch databases,
  checked by the app's own image; retention 30 days plus the oldest set of each month for a year.
  `/up/backup` answers 503 when either is more than a day old.
- **Ingress:** the Cloudflare tunnel (configured in op-works) publishes `getshadetree.com`
  (production) and `staging.getshadetree.com` (staging). Its origin is
  `https://<VM internal hostname>:443`; Puma serves that with a Cloudflare Origin CA certificate
  (TLS 1.2+), and plain HTTP is never published. Thruster is dropped: Cloudflare compresses and
  caches assets at its edge.
- **Forwarded headers:** the tunnel passes the visitor's `Host`, so `config.hosts` is `APP_HOST`
  and headers naming another host are always dropped. Unlike fleet-cmdb, whose dashboard sits
  behind Cloudflare Access, Shadetree's per-IP rate limits need the visitor's address, so
  `X-Forwarded-For` is trusted from the tunnel connector's address (`TRUSTED_PROXIES`) only.

## Consequences

- No hosting bill; the owner keeps the VMs, PostgreSQL, the backup mount, the tunnel and the
  runner running (op-works). A homelab outage is a site outage: the uptime check watches `/up`.
- No point-in-time recovery: up to a day of data can be lost. WAL archiving is the next step if
  that becomes too much.
- The runner is self-hosted on a public repository, so the deploy never runs for pull requests;
  Deploy CI runs on GitHub's runners.
- Cloudflare terminates TLS and sees request paths, including client-link tokens (ADR 0016), as
  kamal-proxy's log would have; nothing on the VM logs paths outside the app's redacted log.
- Deploy CI builds the image and exercises deploy, backup, drill and recovery on every PR that
  changes the app.
- A deploy is not zero-downtime (roughly 30–90 s of 502s at the swap), but a bad release never
  stays: a pre-flight and the migrations run before the swap, and the previous container comes
  back if the new one doesn't answer.
- fleet-cmdb's optional separate jobs container is left out: one small VM per environment and a
  modest job load make one container (Solid Queue in Puma, ADR 0007) enough, and it halves the
  memory. Bringing it back is a second `docker run` of the same image with `bin/jobs`.
- The image is built on the VM, as in fleet-cmdb, which is slow on a 1-vCPU VM. Building on the
  runner and shipping it with `docker save | ssh … docker load` is the later option if builds
  become a problem; it moves the build cache to the runner.
- **Cost:** $0 hosting (the owner's homelab); third parties as in the runbook.
