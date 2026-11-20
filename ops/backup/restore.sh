#!/usr/bin/env bash
# Restores a backup set (backup.sh) into new or empty databases and an empty storage directory
# (PLT-09). Runs inside a throwaway postgres container, started by docker.sh for a restore or the
# restore drill.
#
#   restore.sh <backup set directory> <database name> <storage directory>
#
# primary.dump goes into <database name> and queue.dump into <database name>_queue. Each database
# is created, or reused only if it holds no table, view, sequence, function or type of its own (as
# freshly provisioned ones are), and restored in one transaction, so whole or not at all. The
# storage directory must be empty but for backup/ (the status files) and the image's .keep.
# Exit status: 0 restored; 64 refused, nothing changed; anything else failed part-way.
# Needs createdb, dropdb, pg_restore, psql, tar, sha256sum and the libpq variables.
set -euo pipefail

die() { echo "restore: $*" >&2; exit 1; }
refuse() { echo "restore: $*" >&2; exit 64; } # no tool run here exits 64
sql() { psql -X -At -v ON_ERROR_STOP=1 "$@"; }

[ "$#" -eq 3 ] || refuse "usage: restore.sh <backup set directory> <database name> <storage directory>"
set_dir="$1" db="$2" storage_dir="$3"
[ -d "$set_dir" ] || refuse "$set_dir is not a directory"
[[ "$db" =~ ^[a-z][a-z0-9_]{0,56}$ ]] || refuse "the database name must be lowercase letters, digits and underscores (57 at most)"
if [ -d "$storage_dir" ] && [ -n "$(find "$storage_dir" -mindepth 1 -maxdepth 1 ! -name backup ! -name .keep -print -quit)" ]; then
  refuse "$storage_dir is not empty"
fi
(cd "$set_dir" && sha256sum --check --quiet SHA256SUMS) || refuse "checksum mismatch: this backup set is damaged"

targets=("$db" primary.dump "${db}_queue" queue.dump)
to_create=()
for ((i = 0; i < ${#targets[@]}; i += 2)); do
  name="${targets[$i]}"
  if [ "$(sql -d postgres -c "SELECT count(*) FROM pg_database WHERE datname = '$name'")" = 0 ]; then
    to_create+=("$name")
  else
    # Objects in user schemas that no extension owns.
    objects="$(sql -d "$name" -c "
      WITH user_ns AS (SELECT oid FROM pg_namespace WHERE nspname NOT IN ('pg_catalog', 'information_schema') AND nspname NOT LIKE 'pg_toast%' AND nspname NOT LIKE 'pg_temp%'),
           ext AS (SELECT classid, objid FROM pg_depend WHERE deptype = 'e')
      SELECT (SELECT count(*) FROM pg_class c WHERE c.relnamespace IN (SELECT oid FROM user_ns) AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
                AND NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid = 'pg_class'::regclass AND ext.objid = c.oid))
           + (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN (SELECT oid FROM user_ns)
                AND NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid = 'pg_proc'::regclass AND ext.objid = p.oid))
           + (SELECT count(*) FROM pg_type t WHERE t.typnamespace IN (SELECT oid FROM user_ns) AND t.typtype IN ('e', 'd', 'r', 'm')
                AND NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid = 'pg_type'::regclass AND ext.objid = t.oid))")"
    [ "$objects" = 0 ] || refuse "database $name already exists and holds data ($objects objects); nothing was changed"
  fi
done
if [ "${#to_create[@]}" -gt 0 ]; then
  role="$(sql -d postgres -c "SELECT current_user || ' ' || (rolcreatedb OR rolsuper)::text FROM pg_roles WHERE rolname = current_user")"
  [ "${role##* }" = true ] \
    || refuse "the PostgreSQL role ${role% *} may not create databases, which the restore drill needs. Run once as the PostgreSQL superuser: ALTER ROLE ${role% *} CREATEDB;"
fi

created=()
for ((i = 0; i < ${#targets[@]}; i += 2)); do
  name="${targets[$i]}" file="${targets[$((i + 1))]}"
  if [[ " ${to_create[*]} " == *" $name "* ]]; then createdb "$name" && created+=("$name"); fi
  if ! pg_restore --no-owner --no-privileges --exit-on-error --single-transaction --dbname "$name" "$set_dir/$file"; then
    for done_name in "${created[@]}"; do dropdb --if-exists "$done_name" || true; done
    die "pg_restore of $file into $name failed. The databases this run created were dropped; any that existed before may now be restored: drop and re-create them (empty) before trying again"
  fi
  echo "restore: $file restored into $name"
done
mkdir -p "$storage_dir"
tar -C "$storage_dir" -xf "$set_dir/storage.tar"
echo "restore: databases and uploaded files restored from $set_dir"
