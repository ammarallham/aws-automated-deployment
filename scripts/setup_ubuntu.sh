#!/usr/bin/env bash
#
# setup_ubuntu.sh - install everything the project needs on Ubuntu 22.04 / 24.04:
#   git, python3 + venv, jq, unzip, Terraform, AWS CLI v2, Ansible (inside ./.venv)
# Run once as a NORMAL user (it uses sudo when needed):  ./scripts/setup_ubuntu.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -eq 0 ]]; then
  echo "Run this script as a normal user, not root (it calls sudo itself)." >&2
  exit 1
fi

echo "==> Base packages"
sudo apt-get update
sudo apt-get install -y curl unzip gnupg lsb-release ca-certificates jq git openssl openssh-client \
  python3 python3-venv python3-pip

echo "==> Terraform"
if ! command -v terraform >/dev/null 2>&1; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y terraform
else
  echo "terraform already installed: $(terraform version | head -n1)"
fi

echo "==> AWS CLI v2"
if ! command -v aws >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$tmp/awscliv2.zip"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  sudo "$tmp/aws/install"
  rm -rf "$tmp"
else
  echo "aws already installed: $(aws --version)"
fi

echo "==> Ansible (in $ROOT/.venv)"
python3 -m venv "$ROOT/.venv"
"$ROOT/.venv/bin/pip" install --quiet --upgrade pip
"$ROOT/.venv/bin/pip" install --quiet ansible
"$ROOT/.venv/bin/ansible-galaxy" collection install -r "$ROOT/ansible/requirements.yml"

cat <<'EOF'

All tools installed. Next steps:
  1. aws configure            # enter your Access Key, Secret Key, default region (e.g. eu-central-1)
  2. ./deploy.sh              # build everything
  3. ./destroy.sh             # delete everything when you are done (avoids charges)
EOF
