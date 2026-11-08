#!/usr/bin/env bash
# Checks that Jenkins came up exactly as the code describes: logged-in API works,
# both jobs exist (JCasC + Job DSL) and the build agent is connected over SSH.
# Used by CI after `lab-up.sh --with-jenkins`; handy locally too.
source "$(dirname "$0")/lib.sh"
need curl python3
pw="$(cat "$KEYS_DIR/jenkins_admin_password")"
api() { curl -fsS -u "admin:${pw}" "http://127.0.0.1:8085$1"; }

for job in serverforge-release serverforge-drift; do
  api "/job/${job}/api/json" >/dev/null || die "job ${job} is missing"
  ok "job ${job} exists"
done

log "Waiting for the agent to connect (up to 3 minutes)"
for _ in $(seq 1 36); do
  offline="$(api /computer/lab-agent/api/json | python3 -c 'import json,sys; print(json.load(sys.stdin)["offline"])' || echo True)"
  [[ "$offline" == "False" ]] && { ok "agent lab-agent is online"; exit 0; }
  sleep 5
done
api /computer/lab-agent/log | tail -20 || true
die "agent lab-agent did not come online"
