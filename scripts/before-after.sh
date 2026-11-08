#!/usr/bin/env bash
# The money shot: hardening score of fresh servers, then the same servers after
# site.yml, in one report (reports/before-after/report.html).
#   bash scripts/before-after.sh            # lab (recreates the servers first)
#   INV=aws bash scripts/before-after.sh    # fresh EC2 instances from aws-up.sh
source "$(dirname "$0")/lib.sh"
if [[ "$INV" == lab ]]; then
  bash "$(dirname "$0")/lab-up.sh" --fresh
fi
rm -rf reports/raw/before reports/raw/after
log "1/3 Audit the servers as they are"
play audit.yml -e audit_label=before
log "2/3 Apply the ServerForge baseline (site.yml)"
play site.yml
log "3/3 Audit again"
play audit.yml -e audit_label=after
python3 tools/hardening_report.py --before reports/raw/before --after reports/raw/after \
  --out reports/before-after --label "$INV"
ok "Report: reports/before-after/report.html"
