#!/usr/bin/env bash
# Is the AWS lab running? Which servers, which release, since when?
source "$(dirname "$0")/lib.sh"
need aws
n="$(aws ec2 describe-instances --filters "Name=tag:Project,Values=serverforge" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'length(Reservations[].Instances[])' --output text 2>/dev/null || echo 0)"
if [[ "${n:-0}" == "0" || "$n" == "None" ]]; then
  echo "serverforge-aws: DOWN (costs nothing)"
  exit 0
fi
echo "serverforge-aws: UP - $n instances, ~\$0.02/hour (stop: bash scripts/aws-down.sh)"
# shellcheck disable=SC2016  # the backticks are JMESPath, not shell
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=serverforge" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,IP:PublicIpAddress,Type:InstanceType,Since:LaunchTime}' \
  --output table
if [[ -f inventories/aws/hosts.yml ]]; then
  grep -E 'ansible_host:' inventories/aws/hosts.yml | awk '{print $2}' | while read -r ip; do
    printf '%s  ' "$ip"
    curl -ks --max-time 5 "https://${ip}/api/info" || printf 'app not deployed yet'
    echo
  done
else
  echo "No inventory: the AWS lab is not up (bash scripts/aws-up.sh)."
fi
