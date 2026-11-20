#!/usr/bin/env bash
# Backups of a Shadetree environment (PLT-09, docs/runbooks/operations.md). Runs on the
# environment's VM as the deploy user (in the docker group), from the copy ops/backup/install.sh
# keeps in ~/.local/share/shadetree-<environment>/backup:
#
#   docker.sh <environment> nightly             a backup, then the restore drill on it (the timer
#                                               runs this daily)
#   docker.sh <environment> backup [--force]    one backup now
#   docker.sh <environment> first-backup        start the timer's backup in the background if the
#                                               location holds no set yet (the deploy runs this)
#   docker.sh <environment> restore-drill [SET] restore the newest set (or SET) into scratch
#                                               databases and a scratch volume, and check it
#   docker.sh <environment> restore SET [--force]
#                                               recover a lost server: SET into the app's databases
#                                               and storage volume (the app must be stopped)
#   docker.sh <environment> list                the sets, their sizes and counts
#   docker.sh <environment> delete SET          delete one set (never the newest)
#   docker.sh <environment> pull                pull the PostgreSQL client image
#
# <environment> is staging or production. The PostgreSQL tools run in a throwaway container of
# BACKUP_PG_IMAGE (default postgres:17) on the database's Docker network, as uid 1000 with no
# capabilities, so the database needs no published port and the VM no PostgreSQL client. A backup
# mounts the app's storage volume read-only. After a backup, and after a drill that passed, a status
# file /up/backup reads (storage/backup/last_success, last_drill) is touched by the app's own image,
# in a container with no network.
#
# No secret is stored for the backup: the database host, name, user and password are read when it
# runs from the app container's settings (docker inspect works on a stopped container too) and
# passed to containers by name (docker run -e), never on a command line. The other settings, none
# secret, are in ~/.config/shadetree-<environment>/backup.env, written by the Deploy workflow:
# literal NAME=value lines, read, never sourced.
#
# Backup, drill, restore, delete and the deploy share one lock (lock.sh): a backup or drill waits
# up to an hour for another holder and refuses during a restore; a restore refuses while anything
# else runs. A restore leaves a marker until it succeeds; while it exists, backups, install.sh and
# deploys refuse.
set -euo pipefail

die() { echo "shadetree backup: $*" >&2; exit 1; }
log() { echo "shadetree backup: $*"; }

environment="${1:-}"
[[ "$environment" =~ ^(staging|production)$ ]] || die "usage: docker.sh <staging|production> <command> (see the top of this file)"
shift
ops="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="shadetree-$environment"
volume="${app}_storage"
unit="shadetree-backup@$environment.service"
config="${SHADETREE_BACKUP_ENV:-$HOME/.config/$app/backup.env}"
# shellcheck source=ops/backup/lock.sh
. "$ops/lock.sh"

[ -r "$config" ] || die "$config is missing: the Deploy workflow writes it"
while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
  name="${line%%=*}"
  case "$name" in
    DB_NETWORK | BACKUP_DIR | BACKUP_ALLOW_LOCAL | BACKUP_RETENTION_DAYS | BACKUP_PG_IMAGE)
      printf -v "$name" '%s' "${line#*=}"
      export "${name?}"
      ;;
  esac
done < "$config"
for name in DB_NETWORK BACKUP_DIR; do [ -n "${!name:-}" ] || die "$name is not set in $config"; done
image="${BACKUP_PG_IMAGE:-postgres:17}"

wait_for_docker() { # the timer may fire just after boot (Persistent=true)
  local out=""
  for _ in $(seq 1 24); do
    if out="$(docker info 2>&1 > /dev/null)"; then return 0; fi
    [[ "$out" != *"permission denied"* ]] || die "$(id -un) may not use Docker: add it to the docker group, then restart its systemd instance (as root: systemctl restart user@$(id -u).service)"
    sleep 5
  done
  die "Docker is not running: $out"
}

check_network() {
  docker network inspect "$DB_NETWORK" > /dev/null 2>&1 || die "the Docker network $DB_NETWORK does not exist: start the PostgreSQL container first, or fix DB_NETWORK"
}

check_backup_dir() {
  [ -d "$BACKUP_DIR" ] || die "$BACKUP_DIR does not exist: mount the backup location there and give it to uid 1000 (docs/runbooks/operations.md)"
  case "${BACKUP_ALLOW_LOCAL:-}" in
    1 | true) ;;
    *) mountpoint -q "$BACKUP_DIR" || die "$BACKUP_DIR is not a mount point, so the sets would stay on this VM with the database. Mount an off-machine location there, or set the variable BACKUP_ALLOW_LOCAL=true to accept that" ;;
  esac
}

# The database connection and the app's image, from the app container (running or stopped).
app_settings() {
  local env_lines line
  env_lines="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$app" 2> /dev/null)" \
    || die "there is no $app container: deploy the app first (the backup reads the database settings from it)"
  PGHOST=postgres PGUSER=shadetree PGPASSWORD="" db=shadetree_production
  while IFS= read -r line; do
    case "$line" in
      PGHOST=*) PGHOST="${line#PGHOST=}" ;;
      DATABASE_USER=*) PGUSER="${line#DATABASE_USER=}" ;;
      DATABASE_PASSWORD=*) PGPASSWORD="${line#DATABASE_PASSWORD=}" ;;
      DATABASE_NAME=*) db="${line#DATABASE_NAME=}" ;;
    esac
  done <<< "$env_lines"
  [ -n "$PGPASSWORD" ] || die "the $app container has no DATABASE_PASSWORD setting"
  export PGHOST PGUSER PGPASSWORD
  app_image="$(docker inspect -f '{{.Config.Image}}' "$app")"
}

# docker run of the PostgreSQL image on the database network, as uid 1000 with no capabilities,
# with the libpq variables passed by name. --init, so docker stop or the unit's timeout reaches it.
pg_run() {
  docker run --rm --init --network "$DB_NETWORK" --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges \
    -e HOME=/tmp -e PGHOST -e PGUSER -e PGPASSWORD -v "$ops:/ops:ro" "$@"
}

# A new Docker volume belongs to root; give its top directory to uid 1000.
own_volume() {
  docker run --rm --network none --cap-drop ALL --cap-add CHOWN --security-opt no-new-privileges -v "$1:/v" \
    --entrypoint chown "$image" 1000:1000 /v
}

newest_set() {
  pg_run -v "$BACKUP_DIR:/backups:ro" --entrypoint sh "$image" -c \
    "ls -1d /backups/$app-* 2> /dev/null | sort | tail -n 1 | xargs -r basename"
}

resolve_set() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    name="$(newest_set)"
    [ -n "$name" ] || die "no backup set in $BACKUP_DIR"
  fi
  name="$(basename "$name")"
  [[ "$name" =~ ^$app-[0-9]{8}T[0-9]{6}Z$ ]] || die "$name is not a backup set name ($app-<UTC time>)"
  printf '%s' "$name"
}

set_counts() { pg_run -v "$BACKUP_DIR:/backups:ro" --entrypoint cat "$image" "/backups/$1/counts"; }

do_backup() { # $1: 1 to force
  check_backup_dir
  docker volume inspect "$volume" > /dev/null 2>&1 || die "the volume $volume does not exist: deploy the app first"
  log "backing up $db with $image on the Docker network $DB_NETWORK"
  pg_run --name "$app-backup" -v "$BACKUP_DIR:/backups" -v "$volume:/storage:ro" \
    -e BACKUP_DIR=/backups -e STORAGE_DIR=/storage -e SET_PREFIX="$app" -e BACKUP_DB_NAME="$db" \
    -e BACKUP_FORCE="$1" -e BACKUP_RETENTION_DAYS --entrypoint bash "$image" /ops/backup.sh
  touch_status last_success # only now, after the set is complete
}

# The status files /up/backup reads (BackupStatus). They hold no data.
touch_status() {
  docker run --rm --network none --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges \
    -v "$volume:/rails/storage" --entrypoint sh "$app_image" -c 'mkdir -p storage/backup && touch "storage/backup/$1"' sh "$1"
  log "status file $1 updated"
}

cmd_backup() {
  local force=0
  case "${1:-}" in --force) force=1 ;; "") ;; *) die "usage: docker.sh $environment backup [--force]" ;; esac
  wait_for_docker
  check_network
  take_lock backup 3600
  check_restore_marker
  app_settings
  do_backup "$force"
}

cmd_first_backup() {
  wait_for_docker
  check_backup_dir
  local newest
  newest="$(newest_set)"
  if [ -n "$newest" ]; then
    log "$BACKUP_DIR already holds sets (the newest is $newest): no first backup; the timer takes the next one"
    return 0
  fi
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  systemctl --user start --no-block "$unit"
  log "no set yet: the first backup started in the background (journalctl --user -u $unit)"
}

cmd_restore_drill() {
  wait_for_docker
  check_network
  [ -d "$BACKUP_DIR" ] || die "$BACKUP_DIR does not exist"
  take_lock drill 3600
  app_settings
  local set counts stamp
  set="$(resolve_set "${1:-}")"
  counts="$(set_counts "$set")" || die "$set has no counts file"
  log "restore drill: set $set: $(printf '%s' "$counts" | tr '\n' ' ')"
  stamp="$(date -u +%Y%m%d%H%M%S)"
  scratch="shadetree_restore_drill_${stamp}_$$"
  drill_volume="$app-drill-$stamp-$$"
  tmp="$(mktemp -d)"
  trap drill_cleanup EXIT
  docker volume create "$drill_volume" > /dev/null
  own_volume "$drill_volume"
  log "restore drill: restoring into the scratch databases $scratch and ${scratch}_queue on $PGHOST"
  pg_run -v "$BACKUP_DIR:/backups:ro" -v "$drill_volume:/drill" --entrypoint bash "$image" \
    /ops/restore.sh "/backups/$set" "$scratch" /drill
  # The app's settings, read from its container into a mode-0600 file removed on exit, pointed at
  # the scratch databases (DATABASE_NAME: all four names follow it) and the scratch volume. It only
  # reads, enqueues nothing and opens no cable.
  (umask 077 && docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$app" \
    | grep -v -E '^(DATABASE_NAME|DATABASE_URL|COUNTS|SOLID_QUEUE_IN_PUMA)=' > "$tmp/app.env")
  log "restore drill: checking the restored data with $app_image"
  docker run --rm --init --network "$DB_NETWORK" --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges \
    --env-file "$tmp/app.env" -e DATABASE_NAME="$scratch" -e COUNTS="/backups/$set/counts" \
    -v "$BACKUP_DIR:/backups:ro" -v "$drill_volume:/rails/storage:ro" --entrypoint /rails/bin/rails "$app_image" backup:verify_restore
  touch_status last_drill
}

drill_cleanup() {
  rm -rf "$tmp"
  # shellcheck disable=SC2016 # expanded by the container's shell
  pg_run -e PGOPTIONS='-c client_min_messages=warning' --entrypoint sh "$image" \
    -c 'for name do dropdb --if-exists -d postgres "$name" || exit 1; done' sh "$scratch" "${scratch}_queue" \
    || echo "shadetree backup: could not drop the scratch databases $scratch*; drop them by hand" >&2
  docker volume rm "$drill_volume" > /dev/null 2>&1 || true
}

cmd_restore() {
  local set counts force=0 had_marker=0 rc=0
  [ -n "${1:-}" ] || die "usage: docker.sh $environment restore $app-<UTC time> [--force] (docker.sh $environment list shows the sets)"
  case "${2:-}" in --force) force=1 ;; "") ;; *) die "usage: docker.sh $environment restore SET [--force]" ;; esac
  wait_for_docker
  check_network
  check_backup_dir
  [ "$(docker inspect -f '{{.State.Running}}' "$app" 2> /dev/null || true)" != true ] || die "the $app container is running: stop it first (docker stop $app)"
  take_lock "restore of $1" 0
  app_settings
  set="$(resolve_set "$1")"
  counts="$(set_counts "$set")" || die "$set has no counts file"
  log "restoring $set: $(printf '%s' "$counts" | tr '\n' ' ')"
  if [[ "$counts" == *"businesses=0"* ]] && [ "$force" != 1 ]; then
    die "$set holds no business: it is the backup of an empty database. Pick an older set (docker.sh $environment list), or add --force"
  fi
  docker volume create "$volume" > /dev/null
  own_volume "$volume"
  mkdir -p "$(dirname "$restore_marker")"
  [ ! -e "$restore_marker" ] || had_marker=1
  if [ "$had_marker" = 0 ]; then
    printf '%s' "a restore of $set did not finish (started $(date -u +%Y-%m-%dT%H:%M:%SZ)), so the databases and the volume may be half restored. With the app stopped, drop $db and ${db}_queue (docker exec <postgres container> dropdb -U postgres --if-exists <name>), empty the volume (docker run --rm -v $volume:/s --entrypoint sh $image -c 'rm -rf /s/*'), then run docker.sh $environment restore again. Only if you are sure the restore is complete, delete $restore_marker" > "$restore_marker"
  fi
  pg_run -v "$BACKUP_DIR:/backups:ro" -v "$volume:/storage" --entrypoint bash "$image" \
    /ops/restore.sh "/backups/$set" "$db" /storage || rc=$?
  case "$rc" in
    0) rm -f "$restore_marker" ;;
    64)
      [ "$had_marker" = 0 ] || die "the restore refused before changing anything (above), and the earlier unfinished restore still stands: $(cat "$restore_marker")"
      rm -f "$restore_marker"
      die "the restore refused before changing anything (above)"
      ;;
    *) die "the restore failed part-way (above). $restore_marker stays, so backups and deploys refuse until a restore succeeds" ;;
  esac
  # A backup of the restored state at once, still under the lock, forced (an older set may have
  # been restored on purpose): it becomes the newest set, and /up/backup turns ok.
  log "restored. Backing up the restored state"
  do_backup 1
  log "done. Start the app: docker start $app (or run the Deploy workflow); the next nightly run drills the new set"
}

cmd_list() {
  # shellcheck disable=SC2016 # expanded by the container's shell
  pg_run -v "$BACKUP_DIR:/backups:ro" --entrypoint sh "$image" -c \
    'cd /backups && for set in "$1"-*; do [ -d "$set" ] || continue; printf "%s  %s  %s\n" "$set" "$(du -sh "$set" | cut -f1)" "$(tr "\n" " " < "$set/counts" 2> /dev/null)"; done; true' sh "$app"
}

cmd_delete() {
  local set
  [ -n "${1:-}" ] || die "usage: docker.sh $environment delete SET (docker.sh $environment list shows the sets)"
  wait_for_docker
  take_lock "delete of $1" 0
  set="$(resolve_set "$1")"
  [ "$set" != "$(newest_set)" ] || die "$set is the newest set: not deleted"
  pg_run -v "$BACKUP_DIR:/backups:ro" --entrypoint test "$image" -d "/backups/$set" || die "there is no set $set in $BACKUP_DIR"
  pg_run -v "$BACKUP_DIR:/backups" --entrypoint rm "$image" -rf "/backups/$set"
  log "deleted $set"
}

cmd_pull() {
  if docker pull -q "$image" > /dev/null; then
    log "pulled $image"
  elif docker image inspect "$image" > /dev/null 2>&1; then
    echo "shadetree backup: warning: could not pull $image; the copy already on this VM is used" >&2
  else
    echo "shadetree backup: warning: could not pull $image, and it is not on this VM: backups fail until it can be pulled" >&2
  fi
}

command="${1:-}"
[ "$#" -gt 0 ] && shift
case "$command" in
  nightly)
    cmd_backup
    # The drill in a process of its own, which takes the lock afresh and cleans up on exit: release
    # this one's first (closing the descriptor releases the flock).
    exec 9>&-
    "$0" "$environment" restore-drill
    ;;
  backup) cmd_backup "$@" ;;
  first-backup) cmd_first_backup ;;
  restore-drill) cmd_restore_drill "${1:-}" ;;
  restore) cmd_restore "${1:-}" "${2:-}" ;;
  list) cmd_list ;;
  delete) cmd_delete "${1:-}" ;;
  pull) cmd_pull ;;
  *) die "usage: docker.sh $environment nightly | backup [--force] | first-backup | restore-drill [SET] | restore SET [--force] | list | delete SET | pull" ;;
esac
