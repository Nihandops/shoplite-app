#!/usr/bin/env bash
# Forwards 127.0.0.1:6443 -> control-plane:6443 so kubectl works from your machine.
# Uses the bastion host if Terraform created one (use_bastion=true), otherwise SSM Session Manager.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/terraform"
REGION="${AWS_REGION:-ap-southeast-1}"
BASTION="$(terraform -chdir="$TF" output -raw bastion_public_ip 2>/dev/null || true)"
if [ -n "$BASTION" ]; then
  CP_IP="$(grep -oP 'control-plane ansible_host=\S+ private_ip=\K\S+' "$ROOT/ansible/inventory/hosts.ini")"
  echo "Tunnelling 127.0.0.1:6443 -> ${CP_IP}:6443 via bastion ${BASTION} (Ctrl+C to stop)"
  exec ssh -i ~/.ssh/shoplite -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=30 -N -L 6443:"${CP_IP}":6443 ubuntu@"${BASTION}"
fi
CP_ID="${1:-$(terraform -chdir="$TF" output -raw control_plane_instance_id)}"
echo "Tunnelling 127.0.0.1:6443 -> ${CP_ID}:6443 via SSM (Ctrl+C to stop)"
exec aws ssm start-session --region "$REGION" --target "$CP_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6443"],"localPortNumber":["6443"]}'
