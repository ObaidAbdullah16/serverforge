#!/usr/bin/env bash
# Does every server still match the code? Runs site.yml in check mode: nothing
# is changed, Ansible only reports what it WOULD change.
#   exit 0 = no drift, exit 2 = drift found (details in reports/drift-<time>.txt)
source "$(dirname "$0")/lib.sh"
mkdir -p reports
out="reports/drift-$(date -u +%Y%m%dT%H%M%SZ).txt"
set +e
ANSIBLE_FORCE_COLOR=0 play site.yml --check --diff "$@" | tee "$out"
rc=${PIPESTATUS[0]}
set -e
[[ "$rc" == 0 ]] || die "Ansible failed (exit $rc) - see $out"
changed="$(awk '/PLAY RECAP/{r=1} r && /changed=/{for(i=1;i<=NF;i++) if($i ~ /^changed=/){split($i,a,"="); s+=a[2]}} END{print s+0}' "$out")"
if [[ "$changed" -gt 0 ]]; then
  warn "DRIFT: $changed setting(s) differ from the code. Details: $out"
  warn "Fix: bash scripts/site.sh   (then find out who changed it by hand, and why)"
  exit 2
fi
ok "No drift: every server matches the code"
