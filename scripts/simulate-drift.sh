#!/usr/bin/env bash
# For demos: make the kind of "quick manual fix" that causes real incidents,
# so drift.sh (or the nightly Jenkins job) can catch it.
#   - turns SSH password login back on, on web-prod-1
#   - opens port 8080 in the firewall, on web-prod-1
source "$(dirname "$0")/lib.sh"
inv="$(inventory)" || exit 1
ensure_ansible
host="${1:-web-prod-1}"
ansible "$host" -i "$inv" -b -m ansible.builtin.lineinfile \
  -a "path=/etc/ssh/sshd_config.d/10-serverforge.conf regexp='^PasswordAuthentication' line='PasswordAuthentication yes'"
ansible "$host" -i "$inv" -b -m ansible.builtin.command -a "ufw allow 8080/tcp"
warn "Drift created on $host. Now run: bash scripts/drift.sh"
