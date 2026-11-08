#!/usr/bin/env bash
# Starts the local lab: three Ubuntu 24.04 "servers" in Docker (free).
#
#   bash scripts/lab-up.sh                  # servers only
#   bash scripts/lab-up.sh --with-jenkins   # + Jenkins controller and agent (~2 GB RAM)
#   bash scripts/lab-up.sh --fresh          # throw the old servers away first
source "$(dirname "$0")/lib.sh"
need docker
docker info >/dev/null 2>&1 || die "Docker is not running (start Docker Desktop)"

WITH_JENKINS=0; FRESH=0
for a in "$@"; do
  case "$a" in
    --with-jenkins) WITH_JENKINS=1 ;;
    --fresh) FRESH=1 ;;
    *) die "unknown option $a" ;;
  esac
done

lab_env
if [[ "$FRESH" == 1 ]]; then
  log "Removing the old lab servers"
  compose --profile jenkins down --volumes --remove-orphans >/dev/null 2>&1 || true
fi

log "Building the server image (first time: ~2 minutes)"
compose build web-stg-1 >/dev/null
log "Starting web-stg-1, web-prod-1, web-prod-2"
compose up -d web-stg-1 web-prod-1 web-prod-2
# New containers have new SSH host keys: forget the old ones.
rm -f "$KEYS_DIR/known_hosts"

ensure_ansible
log "Waiting for SSH on all three servers"
for _ in $(seq 1 30); do
  if ansible all -i inventories/lab/hosts.yml -m ansible.builtin.ping >/dev/null 2>&1; then
    ok "Servers are up"
    break
  fi
  sleep 2
done
ansible all -i inventories/lab/hosts.yml -m ansible.builtin.ping >/dev/null || die "Servers did not answer on SSH (docker compose -f lab/docker-compose.yml logs)"

if [[ "$WITH_JENKINS" == 1 ]]; then
  log "Building and starting Jenkins (first time: ~5 minutes)"
  compose --profile jenkins up -d --build jenkins jenkins-agent
  for _ in $(seq 1 90); do
    curl -fs -o /dev/null http://127.0.0.1:8085/login && break
    sleep 3
  done
  ok "Jenkins: http://localhost:8085  user: admin  password: $(cat "$KEYS_DIR/jenkins_admin_password")"
  echo "   Jobs: serverforge-release (Build Now once, then Build with Parameters), serverforge-drift"
  echo "   Jenkins clones the repo from \$SERVERFORGE_REPO_URL (default: your GitHub repo) - push first."
fi

cat <<MSG

Next:
  bash scripts/site.sh                 # build all three servers (~3 minutes)
  bash scripts/build-app.sh && bash scripts/deploy.sh staging
  bash scripts/before-after.sh         # hardening score before vs after (fresh servers)
  https://localhost:8441               # staging in your browser (a self-signed certificate warning is expected)
  bash scripts/lab-down.sh             # remove everything
MSG
