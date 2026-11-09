#!/usr/bin/env bash
# Creates the AWS lab: VPC + 2 x t4g.micro Ubuntu 24.04 (staging, production).
# Cost while up: ~$0.03/hour (2 instances + 2 public IPv4 addresses + disks).
# t4g.micro is "Free tier eligible", so it also starts in an account on the AWS Free plan.
# Another Graviton (arm64) type: SF_AWS_INSTANCE_TYPE=t4g.small bash scripts/aws-up.sh
# Nothing is configured on the servers yet - that is Ansible's job:
#   INV=aws bash scripts/before-after.sh     (audit, harden, audit again)
source "$(dirname "$0")/lib.sh"
need aws terraform ssh-keygen curl python3

mkdir -p "$KEYS_DIR" && chmod 700 "$KEYS_DIR"
[[ -f "$KEYS_DIR/aws_ed25519" ]] || ssh-keygen -q -t ed25519 -N "" -C serverforge-aws -f "$KEYS_DIR/aws_ed25519"

admin="$(my_cidr)"
[[ -n "${SF_EXTRA_ADMIN_CIDRS:-}" ]] && admin="${admin},${SF_EXTRA_ADMIN_CIDRS}"
admin_json="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1].split(",")))' "$admin")"
log "SSH will be allowed from: $admin"

instance_type="${SF_AWS_INSTANCE_TYPE:-t4g.micro}"
require_launchable "$instance_type" 2      # 2 servers: web-stg-1, web-prod-1
log "Servers: 2 x $instance_type"

tf_init
apply_args=(-input=false -var "aws_region=${AWS_REGION}" -var "admin_cidrs=${admin_json}"
            -var "ssh_public_key=$(cat "$KEYS_DIR/aws_ed25519.pub")" -var "instance_type=${instance_type}")
[[ "$AUTO_APPROVE" == 1 ]] && apply_args+=(-auto-approve)
terraform -chdir="$TF_DIR" apply "${apply_args[@]}"

# Inventory for Ansible, from the Terraform outputs
terraform -chdir="$TF_DIR" output -json servers | python3 -c '
import json, sys
servers = json.load(sys.stdin)
admin = sys.argv[1].split(",")
groups = {}
for name, s in sorted(servers.items()):
    groups.setdefault(s["group"], []).append((name, s["ip"]))
lines = ["# Written by scripts/aws-up.sh - do not edit (re-run aws-up.sh instead).", "all:", "  vars:",
         "    sf_admin_cidrs:"] + [f"      - {c}" for c in admin] + ["  children:"]
for g, hosts in sorted(groups.items()):
    lines += [f"    {g}:", "      hosts:"]
    lines += [f"        {n}:\n          ansible_host: {ip}" for n, ip in hosts]
print("\n".join(lines))
' "$admin" > inventories/aws/hosts.yml
rm -f "$KEYS_DIR/known_hosts"   # new servers, new host keys
ok "Inventory: inventories/aws/hosts.yml"

ensure_ansible
log "Waiting for SSH (new instances take ~1 minute)"
for _ in $(seq 1 40); do
  ansible all -i inventories/aws/hosts.yml -m ansible.builtin.ping >/dev/null 2>&1 && break
  sleep 5
done
ansible all -i inventories/aws/hosts.yml -m ansible.builtin.ping >/dev/null || die "Servers do not answer on SSH yet - try again in a minute: bash scripts/aws-status.sh"
ok "Servers are up"
terraform -chdir="$TF_DIR" output servers
cat <<MSG

Next:
  INV=aws bash scripts/before-after.sh                 # audit -> harden -> audit (~6 minutes)
  bash scripts/build-app.sh && INV=aws bash scripts/deploy.sh staging
  bash scripts/aws-down.sh                             # delete everything (stops the cost)
MSG
