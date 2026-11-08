#!/usr/bin/env bash
# Removes the lab containers, Jenkins and their data. Your code and keys stay.
#
#   bash scripts/lab-down.sh          # containers and volumes; keeps the built images so the
#                                     # next lab-up starts in seconds
#   bash scripts/lab-down.sh --all    # also deletes the images it built (frees ~2 GB of disk)
source "$(dirname "$0")/lib.sh"
need docker
ALL=0
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    *) die "unknown option: $a (use --all or nothing)" ;;
  esac
done
lab_env
if [[ "$ALL" == 1 ]]; then
  compose --profile jenkins down --volumes --remove-orphans --rmi local
else
  compose --profile jenkins down --volumes --remove-orphans
fi
rm -f "$KEYS_DIR/known_hosts"
ok "Lab removed"
