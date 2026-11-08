#!/usr/bin/env bash
# Shared helpers for the scripts in this folder. Sourced, not executed.
#
#   INV=lab (default) - the three local Docker "servers" (scripts/lab-up.sh)
#   INV=aws           - the EC2 instances (scripts/aws-up.sh)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$REPO_ROOT/../_setup/config.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/../_setup/config.env"
fi
: "${INV:=lab}"
: "${AWS_REGION:=ap-southeast-2}"
: "${AUTO_APPROVE:=1}"          # AUTO_APPROVE=0 shows the Terraform plan and asks first
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"
[[ -n "${AWS_PROFILE:-}" ]] && export AWS_PROFILE
cd "$REPO_ROOT"                 # ansible.cfg and relative paths assume the repo root

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "'$c' is not installed (see _setup/install-tools-wsl.sh)"
  done
}

inventory() {
  local inv="$REPO_ROOT/inventories/$INV/hosts.yml"
  [[ -f "$inv" ]] || die "No inventory at $inv (INV=$INV). For AWS run scripts/aws-up.sh first."
  echo "$inv"
}

# Use the Ansible pinned in requirements.txt, installed once into .venv.
ensure_ansible() {
  local want
  want="$(grep -E '^ansible==' "$REPO_ROOT/requirements.txt" | cut -d= -f3)"
  # Already installed at the right version (the Jenkins agent image, CI)? Use it.
  if command -v ansible-community >/dev/null 2>&1 && \
     [[ "$(ansible-community --version 2>/dev/null | awk '{print $NF}')" == "$want" ]]; then
    return 0
  fi
  if [[ ! -x "$REPO_ROOT/.venv/bin/ansible-playbook" ]] || \
     ! grep -qx "$want" "$REPO_ROOT/.venv/.ansible-version" 2>/dev/null; then
    need python3
    log "Installing Ansible $want into .venv (first run only, ~1 minute)"
    python3 -m venv "$REPO_ROOT/.venv" || die "python3 -m venv failed (sudo apt install python3-venv)"
    "$REPO_ROOT/.venv/bin/pip" install --quiet --upgrade pip
    "$REPO_ROOT/.venv/bin/pip" install --quiet -r "$REPO_ROOT/requirements.txt"
    echo "$want" > "$REPO_ROOT/.venv/.ansible-version"
  fi
  export PATH="$REPO_ROOT/.venv/bin:$PATH"
}

# play <playbook> [ansible-playbook args...]
play() {
  ensure_ansible
  mkdir -p "$REPO_ROOT/.keys"
  ansible-playbook -i "$(inventory)" "$REPO_ROOT/playbooks/$1" "${@:2}"
}

# Newest artifact in dist/ (built by build-app.sh)
latest_artifact() {
  local f
  # newest by modification time; artifact names never contain spaces
  # shellcheck disable=SC2012
  f="$(ls -1t "$REPO_ROOT"/dist/serverforge-app-*.tar.gz 2>/dev/null | head -n 1 || true)"
  [[ -n "$f" ]] || die "No artifact in dist/. Run: bash scripts/build-app.sh"
  echo "$f"
}

# ---- Terraform (AWS lab) ------------------------------------------------------
TF_DIR="$REPO_ROOT/infra/terraform"
STATE_KEY="serverforge/terraform.tfstate"

aws_account_id() { aws sts get-caller-identity --query Account --output text; }
state_bucket() { echo "${TF_STATE_BUCKET:-tfstate-$(aws_account_id)-${AWS_REGION}}"; }

tf_init() {
  local bucket
  bucket="$(state_bucket)"
  aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1 \
    || die "State bucket $bucket not found: the AWS foundation is not set up (or you are logged in to another account). Start it first: bash _setup/projects.sh up foundation"
  terraform -chdir="$TF_DIR" init -input=false -reconfigure \
    -backend-config="bucket=${bucket}" \
    -backend-config="key=${STATE_KEY}" \
    -backend-config="region=${AWS_REGION}" \
    -backend-config="use_lockfile=true" \
    -backend-config="encrypt=true" >/dev/null
  # A run that lost its AWS login half-way leaves errored.tfstate behind: upload it first, or
  # Terraform would work from the older state in S3.
  if [[ -f "$TF_DIR/errored.tfstate" ]]; then
    printf '[state] Uploading the state an interrupted run could not save (errored.tfstate)\n' >&2
    if terraform -chdir="$TF_DIR" state push errored.tfstate; then
      mv "$TF_DIR/errored.tfstate" "$TF_DIR/errored.tfstate.uploaded-$(date +%Y%m%d-%H%M%S)"
    else
      printf '[state] Could not upload %s/errored.tfstate - if the state is locked, see the guide: "Error acquiring the state lock"\n' "$TF_DIR" >&2
      return 1
    fi
  fi
}

tf_has_resources() { [[ -n "$(terraform -chdir="$TF_DIR" state list 2>/dev/null | grep -v '^data\.' || true)" ]]; }

# Public IP of whoever runs this (your laptop or the GitHub runner), as a /32.
my_cidr() {
  local ip
  ip="$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]')" || die "Could not detect your public IP"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Unexpected public IP: $ip"
  echo "${ip}/32"
}

# ---- Local lab -------------------------------------------------------------------
LAB_DIR="$REPO_ROOT/lab"
KEYS_DIR="$REPO_ROOT/.keys"

# Creates (once) the lab SSH keys and the Jenkins admin password, and exports
# what lab/docker-compose.yml needs.
lab_env() {
  need ssh-keygen
  mkdir -p "$KEYS_DIR" "$LAB_DIR/.secrets"
  chmod 700 "$KEYS_DIR"
  [[ -f "$KEYS_DIR/lab_ed25519" ]]   || ssh-keygen -q -t ed25519 -N "" -C serverforge-lab   -f "$KEYS_DIR/lab_ed25519"
  [[ -f "$KEYS_DIR/agent_ed25519" ]] || ssh-keygen -q -t ed25519 -N "" -C serverforge-agent -f "$KEYS_DIR/agent_ed25519"
  [[ -f "$KEYS_DIR/jenkins_admin_password" ]] || \
    (umask 077; head -c 18 /dev/urandom | base64 | tr -d '/+=' > "$KEYS_DIR/jenkins_admin_password")
  # Docker secrets for Jenkins. The container's jenkins user must read them, so
  # these copies are 0644. They only open throwaway containers on 127.0.0.1.
  install -m 0644 "$KEYS_DIR/lab_ed25519"   "$LAB_DIR/.secrets/lab_ed25519"
  install -m 0644 "$KEYS_DIR/agent_ed25519" "$LAB_DIR/.secrets/agent_ed25519"
  LAB_PUBKEY="$(cat "$KEYS_DIR/lab_ed25519.pub")"
  AGENT_PUBKEY="$(cat "$KEYS_DIR/agent_ed25519.pub")"
  JENKINS_ADMIN_PASSWORD="$(cat "$KEYS_DIR/jenkins_admin_password")"
  export LAB_PUBKEY AGENT_PUBKEY JENKINS_ADMIN_PASSWORD
}

compose() { docker compose -f "$LAB_DIR/docker-compose.yml" "$@"; }
