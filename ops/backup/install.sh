#!/usr/bin/env bash
# Installs an environment's backup on its VM, as the deploy user (PLT-09). The Deploy workflow runs
# it from the shipped code before each deploy replaces the app:
#
#   install.sh <environment>
#
# - copies ops/backup to ~/.local/share/shadetree-<environment>/backup, where the timer runs it;
# - installs the template units shadetree-backup@.service and .timer into ~/.config/systemd/user
#   and enables shadetree-backup@<environment>.timer (daily at 07:30 UTC, caught up after a missed run:
#   a backup, then the restore drill on it);
# - pulls the PostgreSQL client image (a failure only warns).
# It refuses while a restore runs or an unfinished restore left its marker. The deploy user's
# systemd instance must run without a login: once, as root, `loginctl enable-linger <user>`.
set -euo pipefail

die() { echo "backup install: $*" >&2; exit 1; }

environment="${1:-}"
[[ "$environment" =~ ^(staging|production)$ ]] || die "usage: install.sh <staging|production>"
app="shadetree-$environment"
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="$HOME/.local/share/$app/backup"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
user="$(id -un)"
lock_file="$HOME/.local/state/$app/backup.lock"

if [ -f "$lock_file" ] && ! flock -n "$lock_file" true && [[ "$(cat "$lock_file")" == restore* ]]; then
  die "a restore is in progress ($(cat "$lock_file")): deploy when it has finished"
fi
[ ! -e "$HOME/.local/state/$app/restore-incomplete" ] \
  || die "$(cat "$HOME/.local/state/$app/restore-incomplete"): finish the restore before deploying"

[ "$(loginctl show-user "$user" -p Linger --value 2> /dev/null || true)" = yes ] \
  || die "lingering is off for $user, so its backup timer would run only while it is logged in. Run this once on the VM as root: loginctl enable-linger $user"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
for _ in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/bus" ] && break; sleep 1; done
[ -S "$XDG_RUNTIME_DIR/bus" ] || die "the systemd user instance of $user is not running ($XDG_RUNTIME_DIR/bus is missing)"

# Replace the copy whole, so a backup that starts meanwhile sees the old or the new scripts.
mkdir -p "$(dirname "$dest")"
rm -rf "$dest.new" "$dest.old"
cp -R "$src" "$dest.new"
chmod -R u+rwX,go+rX,go-w "$dest.new" # the containers read it as uid 1000; it holds no secret
if [ -e "$dest" ]; then mv "$dest" "$dest.old"; fi
mv "$dest.new" "$dest"
rm -rf "$dest.old"

mkdir -p "$units"
install -m 0644 "$src/shadetree-backup@.service" "$src/shadetree-backup@.timer" "$units/"
systemctl --user daemon-reload
systemctl --user enable --now "shadetree-backup@$environment.timer"
systemctl --user list-timers "shadetree-backup@$environment.timer" --no-pager
"$dest/docker.sh" "$environment" pull || true
