# shellcheck shell=bash
# The backup lock and the restore marker (PLT-09), sourced by docker.sh so backup, restore drill,
# restore and delete take it the same way: one file per environment,
# ~/.local/state/shadetree-<environment>/backup.lock, held with an exclusive flock on file
# descriptor 9 for the life of the script, and a holder line written once it is held.
# ops/deploy/deploy.sh and install.sh follow the same rules. The caller sets app, and defines log and die.
: "${app:?lock.sh needs app}"
lock_file="$HOME/.local/state/$app/backup.lock"
restore_marker="$HOME/.local/state/$app/restore-incomplete"

# $1: what is running; $2: seconds to wait for another holder (0: refuse at once). A restore is
# never waited for: whatever wants the lock refuses while one runs.
take_lock() {
  local holder
  mkdir -p "$(dirname "$lock_file")"
  exec 9>> "$lock_file"
  if ! flock -n 9; then
    holder="$(cat "$lock_file" 2> /dev/null || true)"
    if [ "$2" -gt 0 ] && [[ "$holder" != restore* ]]; then
      log "waiting for: $holder"
      flock -w "$2" 9 || die "still busy after $2 seconds: $holder ($lock_file)"
    else
      die "refused: busy with $holder ($lock_file)"
    fi
  fi
  printf '%s since %s, pid %s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" > "$lock_file"
}

# A restore that did not finish leaves the databases and the volume in an unknown state.
check_restore_marker() {
  [ ! -e "$restore_marker" ] || die "refused: $(cat "$restore_marker")"
}
