#!/bin/sh
# One time (ADR 0026): move Shadetree's SES, email-routing and Worker resources from
# op-works' tf-config state into this directory's state. Only state moves; nothing in AWS or
# Cloudflare is created, changed or destroyed, and the SMTP access keys keep their secrets.
#
#   infra/bin/move-from-op-works.sh <path to op-works checkout>            # dry run
#   infra/bin/move-from-op-works.sh <path to op-works checkout> --apply    # backs up, moves, pushes
#
# Backups go to $BACKUP_DIR (default ~/shadetree-state-backups/<timestamp>/), outside both repos.
set -eu

op_works="${1:?usage: infra/bin/move-from-op-works.sh <op-works checkout> [--apply]}"
apply=false
[ "${2:-}" = "--apply" ] && apply=true

infra="$(cd "$(dirname "$0")/.." && pwd)"
old_root="$(cd "$op_works/tf-config" && pwd)"
backup_dir="${BACKUP_DIR:-$HOME/shadetree-state-backups/$(date +%Y%m%d-%H%M%S)}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "== init"
[ -f "$old_root/.terraform.lock.hcl" ] && [ ! -f "$infra/.terraform.lock.hcl" ] && cp "$old_root/.terraform.lock.hcl" "$infra/"
terraform -chdir="$old_root" init -input=false >/dev/null
terraform -chdir="$infra" init -input=false >/dev/null

echo "== pull and back up"
mkdir -p "$backup_dir"
terraform -chdir="$old_root" state pull > "$work/old.tfstate"
terraform -chdir="$infra" state pull > "$work/new.pulled" || true
cp "$work/old.tfstate" "$backup_dir/op-works-tf-config.tfstate"
cp "$work/new.pulled" "$backup_dir/shadetree-infra.tfstate"
cd "$work"
if [ -s new.pulled ] && [ -n "$(terraform state list -state=new.pulled 2>/dev/null)" ]; then
  echo "infra/ already has resources in its state; refusing. Backups: $backup_dir"
  exit 1
fi
echo "backups in $backup_dir"

# Everything left in op-works' tf-config root is Shadetree's (op-works #53 moved the VMs out).
# Check that before moving anything.
list="$(terraform state list -state=old.tfstate)"
unexpected="$(printf '%s\n' "$list" | grep -v -E '^(aws_|data\.aws_|cloudflare_record\.getshadetree_|cloudflare_email_routing_|cloudflare_workers_script\.shadetree_)' || true)"
if [ -n "$unexpected" ]; then
  echo "op-works' tf-config state holds resources that are not Shadetree's; refusing:"
  printf '  %s\n' $unexpected
  exit 1
fi

echo "== moves (same addresses)"
# Move each top-level resource once; for_each instances move with their resource.
for addr in $(printf '%s\n' "$list" | sed -E 's/\[.*$//' | sort -u); do
  case "$addr" in data.*) continue ;; esac
  $apply && terraform state mv -lock=false -state=old.tfstate -state-out=new.tfstate "$addr" "$addr" >/dev/null
  echo "  $addr"
done
for d in $(printf '%s\n' "$list" | grep '^data\.' | sed -E 's/\[.*$//' | sort -u); do
  $apply && terraform state rm -lock=false -state=old.tfstate "$d" >/dev/null
  echo "  drop data source $d (re-read here)"
done

if ! $apply; then
  echo "== dry run only; nothing pushed. Add --apply to do it."
  exit 0
fi

echo "== push (infra first, then op-works)"
terraform -chdir="$infra" state push "$work/new.tfstate"
terraform -chdir="$old_root" state push "$work/old.tfstate"
echo "Now: terraform -chdir=infra plan  (expect: No changes)"
