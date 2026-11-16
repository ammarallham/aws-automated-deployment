#!/usr/bin/env bash
# Shared helpers for deploy.sh / destroy.sh / scripts. This file is SOURCED, not executed.
# shellcheck disable=SC2034  # variables below are used by the scripts that source this file

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"
ANSIBLE_DIR="$ROOT/ansible"
STATE_DIR="$ROOT/.state"                       # local-only files (git-ignored)
SSH_KEY="$STATE_DIR/id_ed25519"
KNOWN_HOSTS="$STATE_DIR/known_hosts"
VAULT_PASS_FILE="$ROOT/.vault_pass"            # git-ignored
VAULT_FILE="$ANSIBLE_DIR/group_vars/all/vault.yml"   # encrypted, git-ignored
INVENTORY="$ANSIBLE_DIR/inventory/hosts.ini"   # generated, git-ignored

export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
export ANSIBLE_VAULT_PASSWORD_FILE="$VAULT_PASS_FILE"
export TF_IN_AUTOMATION=1

# Use the project virtualenv (created by scripts/setup_ubuntu.sh) when it exists.
if [[ -x "$ROOT/.venv/bin/ansible-playbook" ]]; then
  export VIRTUAL_ENV="$ROOT/.venv"
  export PATH="$ROOT/.venv/bin:$PATH"
fi

# Optional region override: AWS_REGION=eu-west-1 ./deploy.sh
if [[ -n "${AWS_REGION:-}" ]]; then
  export TF_VAR_aws_region="$AWS_REGION"
fi

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_OFF=""
fi

info() { echo "${C_BLUE}==>${C_OFF} $*"; }
ok()   { echo "${C_GREEN}OK${C_OFF}  $*"; }
warn() { echo "${C_YELLOW}WARN${C_OFF} $*" >&2; }
die()  { echo "${C_RED}ERROR${C_OFF} $*" >&2; exit 1; }

require_cmd() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    die "missing tools: ${missing[*]}  ->  run ./scripts/setup_ubuntu.sh (Ubuntu) or install them manually"
  fi
}

tf() { terraform -chdir="$TF_DIR" "$@"; }

tf_output() { tf output -raw "$1"; }

# SSH options used by the helper scripts (same host-key policy as the Ansible inventory).
ssh_opts() {
  echo "-i $SSH_KEY -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$KNOWN_HOSTS"
}
