#!/usr/bin/env bash
# Release the newest artifact in dist/ (or the one given) to staging or production.
#   bash scripts/deploy.sh staging
#   bash scripts/deploy.sh production dist/serverforge-app-1.1.0.tar.gz
source "$(dirname "$0")/lib.sh"
target="${1:-staging}"
[[ "$target" == staging || "$target" == production ]] || die "target must be staging or production"
artifact="${2:-$(latest_artifact)}"
artifact="$(cd "$(dirname "$artifact")" && pwd)/$(basename "$artifact")"
log "Releasing $(basename "$artifact") to $target"
play deploy.yml -e "target=$target" -e "app_artifact=$artifact"
