#!/usr/bin/env bash
# Builds and runs Shadetree on an environment's VM (PLT-09, ADR 0023): the "Build and run" step of
# .github/workflows/deploy.yml, run there over SSH from the shipped code, and by Deploy CI.
#
#   deploy.sh <environment> <dir> <sha> <database network> [published port, default 443]
#
# <environment> is staging or production; it names the container (shadetree-<environment>), its
# storage volume (shadetree-<environment>_storage) and the backup lock. <dir> holds build-<sha>/ (the
# repository's files) and the app's env file shadetree-<environment>.env, which is deleted once
# the container has started.
#
# It takes the backup lock first (~/.local/state/shadetree-<environment>/backup.lock, see
# ops/backup/lock.sh) and holds it until the new app answers: it refuses at once while a restore
# runs or an unfinished restore left its marker, and waits up to 20 minutes for a running backup
# or restore drill (a running pg_dump would hold the new app's migrations back). Background jobs
# run inside the app (SOLID_QUEUE_IN_PUMA in the env file).
set -euo pipefail

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then echo "usage: deploy.sh <environment> <dir> <sha> <database network> [published port]" >&2; exit 2; fi
environment="$1" dir="$2" sha="$3" network="$4" port="${5:-443}"
[[ "$environment" =~ ^(staging|production)$ ]] || { echo "the environment must be staging or production, not '$environment'" >&2; exit 2; }
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "the commit must be a full SHA" >&2; exit 2; }
[[ "$port" =~ ^[0-9]{1,5}$ ]] || { echo "the published port must be a number" >&2; exit 2; }
app="shadetree-$environment"
volume="${app}_storage"
state="$HOME/.local/state/$app"
cd "$dir"
[ -f "$app.env" ] || { echo "$dir/$app.env is missing: the Deploy workflow writes it" >&2; exit 1; }

echo "==> wait for any backup to finish (the backup lock)"
lock_file="$state/backup.lock"
mkdir -p "$state"
exec 9>> "$lock_file"
if ! flock -n 9; then
  holder="$(cat "$lock_file" 2> /dev/null || true)"
  if [[ "$holder" == restore* ]]; then
    echo "a restore is in progress ($holder): the app was not replaced. Deploy again when it has finished" >&2
    exit 1
  fi
  echo "waiting for: $holder"
  flock -w 1200 9 || { echo "still busy after 20 minutes: $holder. The app was not replaced; run the workflow again later" >&2; exit 1; }
fi
if [ -e "$state/restore-incomplete" ]; then
  echo "$(cat "$state/restore-incomplete"): the app was not replaced. Finish the restore first (docs/runbooks/operations.md)" >&2
  exit 1
fi
printf 'deploy of %s since %s, pid %s\n' "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" > "$lock_file"

echo "==> database network $network"
docker network inspect "$network" > /dev/null \
  || { echo "the Docker network $network does not exist: start the PostgreSQL container first, or fix DB_NETWORK" >&2; exit 1; }
echo "==> storage volume $volume"
docker volume create "$volume" > /dev/null
echo "==> build $app:$sha"
docker build --pull -q -t "$app:$sha" -t "$app:latest" "build-$sha" > /dev/null
echo "==> replace the container"
# Stopped first (SIGTERM, up to 30 s), so Solid Queue releases the jobs it claimed.
docker stop -t 30 "$app" > /dev/null 2>&1 || true
docker rm -f "$app" > /dev/null 2>&1 || true
# No capabilities and no privilege gain: the app binds ports above 1024 and needs neither (Chrome,
# for PDFs, runs without its sandbox: app/models/pdf_renderer.rb). Only HTTPS is published.
docker run -d --name "$app" -p "$port:3443" --network "$network" --restart unless-stopped \
  --cap-drop ALL --security-opt no-new-privileges --shm-size 256m \
  -v "$volume:/rails/storage" --env-file "$app.env" "$app:$sha" > /dev/null
rm -f "$app.env"
echo "==> wait for /up (the first start creates and migrates the databases)"
for _ in $(seq 1 60); do
  if docker exec "$app" curl -fsS -o /dev/null http://localhost:3000/up 2> /dev/null; then up=yes; break; fi
  sleep 5
done
if [ -z "${up:-}" ]; then docker logs --tail 100 "$app"; echo "the app did not answer /up" >&2; exit 1; fi
# The HTTPS listener the tunnel uses (-k: this checks the listener; the workflow checked the
# certificate before shipping).
docker exec "$app" curl -fsSk -o /dev/null https://localhost:3443/up \
  || { docker logs --tail 100 "$app"; echo "the app does not answer HTTPS on 3443: are TLS_CERT and TLS_KEY set?" >&2; exit 1; }
docker ps --filter name="^$app\$" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo "/up/jobs: $(docker exec "$app" curl -s http://localhost:3000/up/jobs)"
echo "/up/backup: $(docker exec "$app" curl -s http://localhost:3000/up/backup)"
# Keep the image just deployed and the one before it, for a quick re-run of an earlier deploy.
docker images "$app" --format '{{.Tag}}' | grep -vx -e latest -e "$sha" | tail -n +2 | sed "s/^/$app:/" | xargs -r docker rmi > /dev/null || true
docker image prune -f > /dev/null
