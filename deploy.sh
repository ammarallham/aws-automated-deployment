#!/usr/bin/env bash
#
# deploy.sh - one command to build everything:
#   Terraform (VPC + 2 EC2 + S3)  ->  Python (inventory)  ->  Ansible (Docker + roles)
#   ->  Docker Compose (Flask+Nginx / Postgres)  ->  Bash (health check + first backup)
#
# Usage:  ./deploy.sh            deploy (safe to re-run: every step is idempotent)
#         ./deploy.sh --help
#
# Optional environment variables:
#   AWS_REGION        region to use (default: eu-central-1)
#   ALLOWED_SSH_CIDR  CIDR allowed to SSH, e.g. 1.2.3.4/32 (default: your current public IP)
#   ANSIBLE_EXTRA_ARGS  extra flags for ansible-playbook, e.g. "-vv"
set -Eeuo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/lib.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi

trap 'echo "${C_RED}Deployment failed (line $LINENO).${C_OFF} Fix the error above and re-run ./deploy.sh, or run ./destroy.sh to remove everything." >&2' ERR

###############################################################################
step_preflight() {
  info "[1/8] Pre-flight checks"
  require_cmd terraform aws python3 ansible-playbook ansible-galaxy ansible-vault ssh ssh-keygen curl openssl
  aws sts get-caller-identity >/dev/null 2>&1 \
    || die "AWS credentials not found/valid. Run 'aws configure' (or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)."
  ok "tools installed and AWS credentials work"
}

###############################################################################
step_ssh_key() {
  info "[2/8] SSH key pair (stays on this machine in .state/, git-ignored)"
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  if [[ ! -f "$SSH_KEY" ]]; then
    ssh-keygen -t ed25519 -N "" -C "devops-final-project" -f "$SSH_KEY" -q
    ok "generated $SSH_KEY"
  else
    ok "reusing existing key"
  fi
}

###############################################################################
step_vault() {
  info "[3/8] Ansible Vault (random secrets, encrypted, never committed)"
  if [[ ! -f "$VAULT_PASS_FILE" ]]; then
    [[ ! -f "$VAULT_FILE" ]] || die "$VAULT_FILE exists but $VAULT_PASS_FILE is missing. Restore the password file or delete vault.yml to regenerate."
    (umask 077; openssl rand -base64 32 > "$VAULT_PASS_FILE")
    ok "created vault password file (.vault_pass)"
  fi
  if [[ ! -f "$VAULT_FILE" ]]; then
    local tmp
    tmp="$(mktemp)"
    printf 'vault_postgres_password: "%s"\n' "$(openssl rand -hex 24)" > "$tmp"
    # the password file is picked up from ANSIBLE_VAULT_PASSWORD_FILE (exported by lib.sh)
    ansible-vault encrypt --output "$VAULT_FILE" "$tmp" >/dev/null
    rm -f "$tmp"
    ok "created encrypted $VAULT_FILE"
  else
    ok "vault.yml already exists"
  fi
}

###############################################################################
step_terraform() {
  info "[4/8] Terraform: VPC + 2 EC2 + S3 bucket"

  local cidr="${ALLOWED_SSH_CIDR:-}"
  if [[ -z "$cidr" ]]; then
    local my_ip
    my_ip="$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]')" \
      || die "could not detect your public IP. Set it manually: ALLOWED_SSH_CIDR=1.2.3.4/32 ./deploy.sh"
    [[ "$my_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "unexpected IP detection result: '$my_ip'"
    cidr="$my_ip/32"
  fi
  info "SSH will be allowed only from $cidr"

  export TF_VAR_ssh_public_key
  TF_VAR_ssh_public_key="$(cat "$SSH_KEY.pub")"
  export TF_VAR_allowed_ssh_cidr="$cidr"

  tf init -input=false
  tf apply -input=false -auto-approve
  ok "infrastructure is up"
}

###############################################################################
step_inventory() {
  info "[5/8] Python: generate Ansible inventory from Terraform outputs"
  python3 "$ROOT/scripts/gen_inventory.py"
}

###############################################################################
step_ansible() {
  info "[6/8] Ansible: configure servers (hardening, Docker, Postgres, Flask+Nginx, backup cron)"
  ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml" >/dev/null

  local extra=()
  if [[ -n "${ANSIBLE_EXTRA_ARGS:-}" ]]; then
    read -r -a extra <<< "$ANSIBLE_EXTRA_ARGS"
  fi
  (cd "$ANSIBLE_DIR" && ansible-playbook site.yml "${extra[@]}")
}

###############################################################################
step_health() {
  info "[7/8] Bash: health check (GET /health must return 200)"
  "$ROOT/scripts/health_check.sh"
}

###############################################################################
step_backup_test() {
  info "[8/8] Bash: run the backup script once and verify the upload to S3"
  local db_ip bucket
  db_ip="$(tf_output db_public_ip)"
  bucket="$(tf_output s3_bucket_name)"
  # shellcheck disable=SC2046
  ssh $(ssh_opts) "ubuntu@$db_ip" 'sudo /usr/local/bin/db-backup.sh'
  aws s3 ls "s3://$bucket/backups/" --region "$(tf_output aws_region)" || warn "could not list the bucket from this machine (backup itself succeeded)"
}

###############################################################################
summary() {
  local web_ip db_ip bucket
  web_ip="$(tf_output web_public_ip)"
  db_ip="$(tf_output db_public_ip)"
  bucket="$(tf_output s3_bucket_name)"
  cat <<EOF

${C_GREEN}Deployment finished.${C_OFF}
  App:        http://$web_ip/
  Health:     http://$web_ip/health
  SSH web:    ssh -i $SSH_KEY ubuntu@$web_ip
  SSH db:     ssh -i $SSH_KEY ubuntu@$db_ip
  S3 bucket:  $bucket

Verify idempotency:  ./scripts/check_idempotency.sh   (2nd Ansible run must show changed=0)
Clean up (IMPORTANT to avoid charges):  ./destroy.sh
EOF
}

step_preflight
step_ssh_key
step_vault
step_terraform
step_inventory
step_ansible
step_health
step_backup_test
summary
