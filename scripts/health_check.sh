#!/usr/bin/env bash
#
# health_check.sh - wait until GET /health returns HTTP 200.
#
# Usage:  scripts/health_check.sh [URL]
#         (default URL: http://<web_public_ip>/health, read from Terraform outputs)
# Env:    RETRIES=30  SLEEP=5   (30 tries x 5 s = up to 2.5 minutes)
# Exit:   0 = healthy, 1 = still unhealthy after all retries
set -uo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

RETRIES="${RETRIES:-30}"
SLEEP="${SLEEP:-5}"

url="${1:-}"
if [[ -z "$url" ]]; then
  require_cmd terraform
  web_ip="$(tf_output web_public_ip)" || die "cannot read web_public_ip from Terraform (is the stack deployed?)"
  url="http://$web_ip/health"
fi

info "checking $url (up to $RETRIES tries, ${SLEEP}s apart)"
for ((i = 1; i <= RETRIES; i++)); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)"
  if [[ "$code" == "200" ]]; then
    ok "health check passed on try $i: $(curl -s --max-time 5 "$url")"
    exit 0
  fi
  echo "  try $i/$RETRIES -> HTTP $code"
  sleep "$SLEEP"
done

die "health check FAILED: $url did not return 200"
