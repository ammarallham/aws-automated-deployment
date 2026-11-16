#!/usr/bin/env bash
#
# check_idempotency.sh - run the Ansible playbook again and prove it changes nothing.
# Passes only if every host shows changed=0 and failed=0 / unreachable=0 in the PLAY RECAP.
set -Eeuo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd ansible-playbook
[[ -f "$INVENTORY" ]] || die "no inventory found - run ./deploy.sh first"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

info "running ansible-playbook a second time"
(cd "$ANSIBLE_DIR" && ansible-playbook site.yml) | tee "$log"

recap="$(grep -E '^[A-Za-z0-9_.-]+ +: ok=' "$log" || true)"
[[ -n "$recap" ]] || die "could not find the PLAY RECAP in the output"

echo
info "PLAY RECAP"
echo "$recap"

if echo "$recap" | grep -Eq 'changed=[1-9]|failed=[1-9]|unreachable=[1-9]'; then
  die "NOT idempotent: some tasks reported changes or failures (see tasks marked 'changed' above)"
fi
ok "idempotent: changed=0 on every host"
