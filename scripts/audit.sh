#!/usr/bin/env bash
# Lynis audit of every server -> reports/raw/<label>/<host>.dat + a report.
#   bash scripts/audit.sh             # label "latest"
#   bash scripts/audit.sh before
source "$(dirname "$0")/lib.sh"
label="${1:-latest}"
rm -rf "reports/raw/$label"
play audit.yml -e "audit_label=$label"
python3 tools/hardening_report.py --after "reports/raw/$label" --out "reports/$label" --label "$INV"
ok "Report: reports/$label/report.html"
