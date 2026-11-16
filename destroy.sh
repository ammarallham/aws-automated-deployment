#!/usr/bin/env bash
#
# destroy.sh - delete EVERYTHING that deploy.sh created in AWS (EC2, VPC, S3 + backups, IAM).
#
# Usage:  ./destroy.sh          asks for confirmation
#         ./destroy.sh --yes    no question asked
#         ./destroy.sh --purge  also delete local SSH key, vault password and encrypted vault
set -Eeuo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/lib.sh"

ASSUME_YES=false
PURGE=false
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=true ;;
    --purge)  PURGE=true ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $arg" ;;
  esac
done

require_cmd terraform

if [[ ! -f "$TF_DIR/terraform.tfstate" ]]; then
  ok "no Terraform state found - nothing to destroy in AWS"
else
  if [[ "$ASSUME_YES" != true ]]; then
    warn "This will permanently delete the EC2 instances, VPC and the S3 bucket WITH all backups."
    read -r -p "Type 'yes' to continue: " answer
    [[ "$answer" == "yes" ]] || die "aborted"
  fi

  # Required variables have no default; their values do not matter for destroy.
  export TF_VAR_ssh_public_key="destroy-placeholder"
  export TF_VAR_allowed_ssh_cidr="0.0.0.0/32"

  info "terraform destroy"
  tf init -input=false
  tf destroy -input=false -auto-approve
  ok "all AWS resources deleted"
fi

rm -f "$INVENTORY" "$KNOWN_HOSTS"

if [[ "$PURGE" == true ]]; then
  rm -rf "$STATE_DIR" "$VAULT_PASS_FILE" "$VAULT_FILE"
  ok "local key / vault files removed"
fi
