#!/usr/bin/env bash
# Deletes the AWS lab (servers, disks, network). Safe to run when nothing is up.
#
#   bash scripts/aws-down.sh          # everything in AWS is deleted (nothing is kept there)
#   bash scripts/aws-down.sh --all    # also deletes the lab's SSH key on your laptop (a new one is made next time)
source "$(dirname "$0")/lib.sh"
need aws terraform
ALL=0
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    *) die "unknown option: $a (use --all or nothing)" ;;
  esac
done
tf_init
if ! tf_has_resources; then
  ok "Nothing to delete - the AWS lab is not running"
  [[ "$ALL" == 1 ]] && rm -f "$KEYS_DIR/aws_ed25519" "$KEYS_DIR/aws_ed25519.pub"
  exit 0
fi
args=(-input=false -var "aws_region=${AWS_REGION}" -var 'admin_cidrs=["127.0.0.1/32"]' -var "ssh_public_key=unused")
[[ "$AUTO_APPROVE" == 1 ]] && args+=(-auto-approve)
terraform -chdir="$TF_DIR" destroy "${args[@]}"
rm -f inventories/aws/hosts.yml "$KEYS_DIR/known_hosts"
[[ "$ALL" == 1 ]] && rm -f "$KEYS_DIR/aws_ed25519" "$KEYS_DIR/aws_ed25519.pub"
ok "AWS lab deleted - it costs nothing now"
