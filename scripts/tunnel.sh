#!/usr/bin/env bash
# Opens an SSM port-forward to the Kubernetes API (127.0.0.1:6443 -> control-plane:6443).
# Keep it running in its own terminal tab. Nodes stay private; no SSH/6443 is open to the internet.
set -euo pipefail
REGION="${AWS_REGION:-ap-southeast-1}"
CP_ID="${1:-$(cd "$(dirname "$0")/../terraform" && terraform output -raw control_plane_instance_id)}"
echo "Tunnelling 127.0.0.1:6443 -> ${CP_ID}:6443 (Ctrl+C to stop)"
exec aws ssm start-session --region "$REGION" --target "$CP_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6443"],"localPortNumber":["6443"]}'
