#!/usr/bin/env bash
# Builds the release artifact: dist/serverforge-app-<version>.tar.gz + .sha256
#
#   bash scripts/build-app.sh                 # version from app/VERSION
#   VERSION=1.2.0 bash scripts/build-app.sh
#   bash scripts/build-app.sh --broken        # a release that fails its health check
#
# The tarball is reproducible: same source -> same bytes -> same checksum
# (sorted file list, fixed owner and timestamps, gzip without a timestamp).
source "$(dirname "$0")/lib.sh"
need tar gzip sha256sum

BROKEN=0
[[ "${1:-}" == "--broken" ]] && BROKEN=1
VERSION="${VERSION:-$(tr -d '[:space:]' < app/VERSION)}"
[[ "$VERSION" =~ ^[0-9A-Za-z.+_-]+$ ]] || die "Invalid version: $VERSION"
[[ "$BROKEN" == 1 ]] && VERSION="${VERSION}-broken"

# Fixed timestamp for every file: the last commit's time (or 2026-01-01 outside Git)
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || echo 1767225600)}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/release" dist
cp -r app/serverforge_app "$work/release/"
find "$work/release" -name '__pycache__' -type d -prune -exec rm -rf {} +
echo "$VERSION" > "$work/release/VERSION"
[[ "$BROKEN" == 1 ]] && echo "This release fails /healthz on purpose (rollback demo)." > "$work/release/BROKEN"

out="dist/serverforge-app-${VERSION}.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w' --mtime="@${SOURCE_DATE_EPOCH}" \
    -C "$work/release" -cf - . | gzip -n -9 > "$out"
( cd dist && sha256sum "$(basename "$out")" > "$(basename "$out").sha256" )
ok "Built $out"
cat "${out}.sha256"
