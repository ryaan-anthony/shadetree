#!/usr/bin/env bash
# One backup set of a Shadetree environment (PLT-09, docs/runbooks/operations.md). Runs inside a
# throwaway postgres container on the database's Docker network, started by docker.sh, which
# checks the backup location on the VM, holds the backup lock, and touches the status file
# /up/backup reads once this has succeeded.
#
# Writes <BACKUP_DIR>/<SET_PREFIX>-<UTC time>/ holding:
#   primary.dump   pg_dump (custom format) of the app's database
#   queue.dump     the Solid Queue database: scheduled and waiting jobs survive a restore
#   storage.tar    the uploaded files (Active Storage, the app's storage volume, without backup/)
#   counts         row counts taken just before the dump, which the restore drill checks
#   SHA256SUMS     checksums of the files above
# The cache and cable databases hold only short-lived data and are not dumped; the app recreates
# their tables when it starts. A set appears whole or not at all, then old sets are pruned.
#
# A database with no business where the newest set had some is refused: that is the empty database
# of a rebuilt server, and its set would become the newest and let retention prune the good ones.
# BACKUP_FORCE=1 writes it anyway (after a deliberate fresh start).
#
#   BACKUP_DIR             required: where the sets go (checked on the VM by docker.sh)
#   STORAGE_DIR            required: the app's storage volume, mounted read-only
#   SET_PREFIX             required: shadetree-staging or shadetree-production
#   BACKUP_DB_NAME         required: the app's database; the queue database is <name>_queue
#   BACKUP_RETENTION_DAYS  default 30: daily sets older than this are deleted, except the oldest
#                          set of each month, kept for a year; the newest 3 are always kept
#   BACKUP_KEEP_MONTHLY    default true; false keeps no monthly sets (staging's default)
#   BACKUP_FORCE           1: write the set even if it looks like an empty database (see above)
# The database is reached with the libpq variables (PGHOST, PGUSER, PGPASSWORD).
set -euo pipefail
umask 077 # the sets hold every business's data

die() { echo "backup: $*" >&2; exit 1; }
log() { echo "backup: $*"; }

: "${BACKUP_DIR:?}" "${STORAGE_DIR:?}" "${SET_PREFIX:?}" "${BACKUP_DB_NAME:?}"
db="$BACKUP_DB_NAME"
retention_days="${BACKUP_RETENTION_DAYS:-30}"
keep_min=3
[[ "$retention_days" =~ ^[0-9]+$ ]] || die "BACKUP_RETENTION_DAYS must be a whole number"
[ -d "$BACKUP_DIR" ] || die "$BACKUP_DIR does not exist"

# pg_dump refuses a newer server anyway; say plainly which versions met.
server_major="$(psql -X -At -v ON_ERROR_STOP=1 -d "$db" -c "SELECT current_setting('server_version_num')::int / 10000")"
client_major="$(pg_dump --version | sed -n 's/^pg_dump (PostgreSQL) \([0-9]*\).*/\1/p')"
[[ "$server_major" =~ ^[0-9]+$ && "$client_major" =~ ^[0-9]+$ ]] || die "could not read the PostgreSQL versions (server '$server_major', pg_dump '$client_major')"
if [ "$client_major" -lt "$server_major" ]; then
  die "pg_dump is PostgreSQL $client_major but the server is PostgreSQL $server_major: set the variable BACKUP_PG_IMAGE to postgres:$server_major or newer"
fi

sets_newest_first() { find "$BACKUP_DIR" -maxdepth 1 -type d -name "$SET_PREFIX-*" | sort -r; }
count_in() { sed -n "s/^$2=\([0-9]*\)$/\1/p" "$1/counts" 2> /dev/null; }
# Each count is its own assignment, so a failed query stops the backup.
count() {
  local value
  value="$(psql -X -At -v ON_ERROR_STOP=1 -d "$db" -c "SELECT count(*) FROM $1")"
  [[ "$value" =~ ^[0-9]+$ ]] || die "counting $1 returned '$value'"
  printf '%s' "$value"
}
counts=""
for table in users businesses clients active_storage_blobs; do counts+="$table=$(count "$table")"$'\n'; done
log "$(printf '%s' "$counts" | tr '\n' ' ')"
businesses="$(printf '%s' "$counts" | sed -n 's/^businesses=//p')"

newest="$(sets_newest_first | head -n 1)"
if [ -n "$newest" ] && [ "${BACKUP_FORCE:-}" != 1 ] && [ "$businesses" -eq 0 ] && [ "$(count_in "$newest" businesses)" -gt 0 ] 2> /dev/null; then
  die "refused: the database holds no business, but the newest set $(basename "$newest") holds $(count_in "$newest" businesses). This looks like the empty database of a rebuilt server: restore a set first (docs/runbooks/operations.md, Restore). Nothing was written or pruned. After a deliberate fresh start, run docker.sh <environment> backup --force"
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
final="$BACKUP_DIR/$SET_PREFIX-$stamp"
work="$BACKUP_DIR/.incoming-$SET_PREFIX-$stamp"
[ ! -e "$final" ] || die "$final already exists"
mkdir "$work"
trap 'rm -rf "$work"' EXIT
printf '%s' "$counts" > "$work/counts"
dump() {
  pg_dump --format=custom --no-owner --no-privileges --file "$work/$2" "$1"
  pg_restore --list "$work/$2" > /dev/null # it must read back
}
dump "$db" primary.dump
dump "${db}_queue" queue.dump
tar -C "$STORAGE_DIR" --exclude=./backup -cf "$work/storage.tar" .
(cd "$work" && sha256sum primary.dump queue.dump storage.tar counts > SHA256SUMS)
mv "$work" "$final"
trap - EXIT
log "wrote $final ($(du -sh "$final" | cut -f1))"

# Retention, by the UTC time in each set's name (a mount may not keep mtimes): the newest
# keep_min always stay; older than retention_days goes, unless it is the oldest set of its month
# and less than a year old.
now="$(date -u +%s)"
age_of() {
  local t="${1##*-}"
  [[ "$t" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$ ]] || return 0
  echo $((now - $(date -u -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}" +%s)))
}
month_of() { local t="${1##*-}"; printf '%s' "${t:0:6}"; }
mapfile -t sets < <(sets_newest_first)
declare -A oldest_of_month=()
for set in "${sets[@]}"; do oldest_of_month["$(month_of "$set")"]="$set"; done # newest first: the last one wins
for i in "${!sets[@]}"; do
  [ "$i" -lt "$keep_min" ] && continue
  set="${sets[$i]}"
  age="$(age_of "$(basename "$set")")"
  if [ -z "$age" ] || [ "$age" -le $((retention_days * 86400)) ]; then continue; fi
  if [ "${BACKUP_KEEP_MONTHLY:-true}" != false ] && [ "${oldest_of_month[$(month_of "$set")]}" = "$set" ] && [ "$age" -lt $((366 * 86400)) ]; then continue; fi
  rm -rf "$set"
  log "pruned $set"
done
# A run that was killed leaves its .incoming directory; remove those more than a day old.
while IFS= read -r stale; do
  age="$(age_of "$(basename "$stale")")"
  if [ -n "$age" ] && [ "$age" -gt 86400 ]; then rm -rf "$stale" && log "removed $stale, left by an interrupted run"; fi
done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -name ".incoming-$SET_PREFIX-*")
log "done"
