#!/usr/bin/env bash
# Build/repair every server from the code (safe to run any time).
#   bash scripts/site.sh                 # lab, all servers
#   INV=aws bash scripts/site.sh --limit staging
source "$(dirname "$0")/lib.sh"
play site.yml "$@"
