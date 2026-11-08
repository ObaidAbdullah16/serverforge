#!/usr/bin/env bash
# Go back one release on staging or production.
source "$(dirname "$0")/lib.sh"
target="${1:-staging}"
play rollback.yml -e "target=$target"
