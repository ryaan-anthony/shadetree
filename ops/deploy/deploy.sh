#!/usr/bin/env bash
# Builds and runs Shadetree on an environment's VM (PLT-09, ADR 0023): the "Build and run" step of
# .github/workflows/deploy.yml, run there over SSH from the shipped code, and by Deploy CI.
#
#   deploy.sh <environment> <dir> <sha> <database network> [published port, default 443]
#
# <environment> is staging or production; it names the container (shadetree-<environment>), its
# storage volume (shadetree-<environment>_storage) and the backup lock. <dir> holds build-<sha>/ (the
# repository's files) and the app's env file shadetree-<environment>.env, deleted when this ends.
# Optional settings from the environment: APP_MEMORY (the container's memory limit, default 1g)
# and MIN_FREE_MB (free disk the deploy needs, default 3072).
#
# Order, so that a bad release never takes a working site down:
#   1. the backup lock (~/.local/state/shadetree-<environment>/backup.lock, ops/backup/lock.sh): it
#      refuses during a restore or after an unfinished one, and waits up to 20 minutes for a backup
#      or drill (a running pg_dump would hold the migrations back);
#   2. free disk, then the image: built once per commit, so re-running an earlier deploy (a
#      rollback) reuses its image;
#   3. a pre-flight in a one-off container of the new image with the new settings: the app boots
#      (which parses every setting, TRUSTED_PROXIES included) and reaches the database; then the
#      migrations (db:prepare), still with the old container serving. Migrations must therefore be
#      backward-compatible with the previous release (the runbook's rule), which rollback relies on
#      anyway;
#   4. the swap: the old container is stopped and kept as shadetree-<environment>-previous, the new
#      one started. If it doesn't answer /up and HTTPS, the old container is started again, with its
#      own settings, and the message says whether the site is up.
# Each failure message says whether the site is UP or DOWN and what to do next.
set -euo pipefail

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then echo "usage: deploy.sh <environment> <dir> <sha> <database network> [published port]" >&2; exit 2; fi
environment="$1" dir="$2" sha="$3" network="$4" port="${5:-443}"
[[ "$environment" =~ ^(staging|production)$ ]] || { echo "the environment must be staging or production, not '$environment'" >&2; exit 2; }
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "the commit must be a full SHA" >&2; exit 2; }
[[ "$port" =~ ^[0-9]{1,5}$ ]] || { echo "the published port must be a number" >&2; exit 2; }
memory="${APP_MEMORY:-1g}" min_free_mb="${MIN_FREE_MB:-3072}"
[[ "$memory" =~ ^[0-9]+[mg]$ ]] || { echo "APP_MEMORY must look like 1g or 1536m" >&2; exit 2; }
[[ "$min_free_mb" =~ ^[0-9]+$ ]] || { echo "MIN_FREE_MB must be a whole number" >&2; exit 2; }
app="shadetree-$environment"
previous="$app-previous"
image="$app:$sha"
volume="${app}_storage"
state="$HOME/.local/state/$app"
cd "$dir"
env_file="$PWD/$app.env"
[ -f "$env_file" ] || { echo "$env_file is missing: the Deploy workflow writes it" >&2; exit 1; }
trap 'rm -f "$env_file"' EXIT

running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2> /dev/null || true)" = true ]; }
status_line() { if running "$app"; then echo "The site is UP on $(docker inspect -f '{{.Config.Image}}' "$app")"; else echo "The site is DOWN"; fi; }
fail() { echo "deploy failed: $1. $(status_line). $2" >&2; exit 1; }
answers() { # the plain health check inside the container, and the HTTPS listener the tunnel uses
  for _ in $(seq 1 "$2"); do
    if docker exec "$1" curl -fsS -o /dev/null http://localhost:3000/up 2> /dev/null \
      && docker exec "$1" curl -fsSk -o /dev/null https://localhost:3443/up 2> /dev/null; then return 0; fi
    sleep 3
  done
  return 1
}
free_mb() { df -Pm "$1" | awk 'NR == 2 { print $4 }'; }

echo "==> wait for any backup to finish (the backup lock)"
lock_file="$state/backup.lock"
mkdir -p "$state/logs"
exec 9>> "$lock_file"
if ! flock -n 9; then
  holder="$(cat "$lock_file" 2> /dev/null || true)"
  [[ "$holder" != restore* ]] || fail "a restore is in progress ($holder)" "Deploy again when it has finished."
  echo "waiting for: $holder"
  flock -w 1200 9 || fail "still busy after 20 minutes: $holder" "Run the workflow again later."
fi
[ ! -e "$state/restore-incomplete" ] || fail "$(cat "$state/restore-incomplete")" "Finish the restore first (docs/runbooks/operations.md)."
printf 'deploy of %s since %s, pid %s\n' "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" > "$lock_file"

# A deploy that was killed half-way can leave the old container renamed: put it back first.
if ! docker inspect "$app" > /dev/null 2>&1 && docker inspect "$previous" > /dev/null 2>&1; then
  echo "==> an earlier deploy left $previous: restoring it as $app"
  docker rename "$previous" "$app"
  running "$app" || docker start "$app" > /dev/null
fi
docker rm -f "$previous" > /dev/null 2>&1 || true

echo "==> database network $network"
docker network inspect "$network" > /dev/null 2>&1 \
  || fail "the Docker network $network does not exist" "Start the PostgreSQL container first, or fix DB_NETWORK."
docker volume create "$volume" > /dev/null

docker_root="$(docker info -f '{{.DockerRootDir}}')"
for path in "$docker_root" "$HOME"; do
  free="$(free_mb "$path")"
  [ "$free" -ge "$min_free_mb" ] || fail "only ${free} MB free on $path (the deploy needs ${min_free_mb} MB)" \
    "Free some space (docker system df; docker builder prune), or grow the disk, and run the workflow again."
done

if docker image inspect "$image" > /dev/null 2>&1; then
  echo "==> $image is already built: reusing it"
else
  echo "==> build $image"
  docker build --pull --progress=plain -t "$image" "build-$sha" 2>&1 | grep -E '^#[0-9]+ (\[|DONE|ERROR|CACHED)|^ERROR|error:' || true
  docker image inspect "$image" > /dev/null 2>&1 || fail "the image did not build (above)" "Fix the build on main and deploy again."
fi

# The container's settings, the same for the pre-flight, the app and nothing else. No capabilities
# and no privilege gain; a read-only root file system with in-memory /tmp, tmp/, log/ and HOME
# (Chrome, for PDFs, runs without its sandbox and writes its profile to /tmp and HOME); memory and
# log size capped for a small VM.
# shellcheck disable=SC2054 # the commas are tmpfs mount options
hardening=(--cap-drop ALL --security-opt no-new-privileges --read-only
  --tmpfs /tmp:size=256m --tmpfs /rails/tmp:size=128m,uid=1000,gid=1000 --tmpfs /rails/log:size=16m,uid=1000,gid=1000
  --tmpfs /home/rails:size=64m,uid=1000,gid=1000 --shm-size 256m --memory "$memory")
oneoff() { docker run --rm --network "$network" "${hardening[@]}" -v "$volume:/rails/storage" --env-file "$env_file" "$image" "$@"; }

echo "==> pre-flight: the new release boots with these settings and reaches the database"
oneoff ./bin/rails runner 'ActiveRecord::Base.connection.select_value("SELECT 1") == 1 or abort("the database did not answer")' 2>&1 | tail -n 20 \
  || fail "the new release does not boot with these settings, or can't reach the database (above); nothing was changed" "Fix the setting in the GitHub environment, or the code, and deploy again."
echo "==> migrate (db:prepare), with the old release still serving"
oneoff ./bin/rails db:prepare 2>&1 | tail -n 40 \
  || fail "the migrations failed (above); the old release keeps running on whatever they changed" "Fix the migration and deploy again; a migration that ran half-way may need a restore (runbook)."

echo "==> replace the container"
had_previous=no
if docker inspect "$app" > /dev/null 2>&1; then
  # Stopped first (SIGTERM, up to 30 s), so Solid Queue releases the jobs it claimed; kept until
  # the new one answers.
  docker stop -t 30 "$app" > /dev/null
  docker rename "$app" "$previous"
  had_previous=yes
fi
docker run -d --name "$app" -p "$port:3443" --network "$network" --restart unless-stopped "${hardening[@]}" \
  --log-opt max-size=10m --log-opt max-file=5 -v "$volume:/rails/storage" --env-file "$env_file" "$image" > /dev/null

save_logs() { # $1 the container: its log, before it's removed (the newest 5 are kept)
  local tag
  tag="$(docker inspect -f '{{.Config.Image}}' "$1" | sed 's/.*://')"
  docker logs "$1" > "$state/logs/$app-$tag-$(date -u +%Y%m%dT%H%M%SZ).log" 2>&1 || true
  find "$state/logs" -maxdepth 1 -name "$app-*.log" -printf '%T@ %p\n' | sort -rn | tail -n +6 | cut -d' ' -f2- | xargs -r rm -f
}

echo "==> wait for /up and HTTPS"
if ! answers "$app" 40; then
  docker logs --tail 100 "$app" >&2 || true
  save_logs "$app"
  docker rm -f "$app" > /dev/null
  if [ "$had_previous" = yes ]; then
    echo "==> the new release did not answer: starting the previous one again" >&2
    docker rename "$previous" "$app"
    docker start "$app" > /dev/null
    if answers "$app" 40; then
      fail "the new release did not answer /up or HTTPS (its log is above); rolled back" "Fix it and deploy again."
    fi
    fail "the new release did not answer, and the previous one didn't come back either" "Check docker logs $app and the database; re-run an earlier deploy."
  fi
  fail "the app did not answer /up or HTTPS (above); are TLS_CERT and TLS_KEY right?" "Fix it and deploy again."
fi
if [ "$had_previous" = yes ]; then save_logs "$previous"; docker rm -f "$previous" > /dev/null; fi

docker ps --filter name="^$app\$" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo "/up/jobs: $(docker exec "$app" curl -s http://localhost:3000/up/jobs)"
echo "/up/backup: $(docker exec "$app" curl -s http://localhost:3000/up/backup)"
# Keep this release and the two before it (for a rollback without a build), newest first.
docker images "$app" --format '{{.CreatedAt}} {{.Repository}}:{{.Tag}}' | sort -r | awk '{ print $NF }' \
  | grep -vx "$image" | tail -n +3 | xargs -r docker rmi > /dev/null 2>&1 || true
docker image prune -f > /dev/null
docker builder prune -f --filter until=168h > /dev/null 2>&1 || true
echo "Deployed $sha. The site is UP."
