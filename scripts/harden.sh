#!/usr/bin/env bash
# Security baseline only (SSH, users, firewall, fail2ban, patching, kernel settings).
source "$(dirname "$0")/lib.sh"
play harden.yml "$@"
