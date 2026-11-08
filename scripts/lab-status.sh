#!/usr/bin/env bash
# What is running in the lab, and which release each server runs.
source "$(dirname "$0")/lib.sh"
need docker curl
lab_env
running="$(compose --profile jenkins ps --status running -q 2>/dev/null | wc -l)"
if [[ "$running" -gt 0 ]]; then
  echo "serverforge (lab): UP - $running containers on your laptop, free (stop: bash scripts/lab-down.sh)"
else
  echo "serverforge (lab): DOWN (start: bash scripts/lab-up.sh)"
  exit 0
fi
compose --profile jenkins ps
echo
for port in 8441 8442 8443; do
  printf '127.0.0.1:%s  ' "$port"
  curl -ks --max-time 3 "https://127.0.0.1:${port}/api/info" || printf 'not answering'
  echo
done
