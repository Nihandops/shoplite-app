#!/usr/bin/env bash
# shellcheck disable=SC2046  # $(v X) intentionally word-splits into "--version X" or nothing
# Installs cluster add-ons with Helm (run once, after Ansible, with scripts/tunnel.sh running):
#   local-path storage, metrics-server, Traefik (NodePort 30080 behind the ALB),
#   kube-prometheus-stack, Loki, Tempo, Alloy, ArgoCD.
# Pin chart versions by exporting e.g. KPS_VERSION=77.0.0 (blank = latest).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$ROOT/ansible/kubeconfig}"
v() { [ -n "${1:-}" ] && echo "--version $1" || true; }

: "${GRAFANA_ADMIN_PASSWORD:?export GRAFANA_ADMIN_PASSWORD=<strong password>}"
: "${SLACK_WEBHOOK_URL:?export SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...  (or a https://webhook.site URL)}"

echo "==> helm repos"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo add traefik https://traefik.github.io/charts >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update >/dev/null

echo "==> local-path storage (default StorageClass)"
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.32/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "==> metrics-server (needed by the HPA)"
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system \
  -f "$ROOT/platform/metrics-server.yaml" $(v "${METRICS_SERVER_VERSION:-}") --wait

echo "==> namespaces + out-of-band secrets (never in Git)"
for ns in monitoring traefik argocd shoplite shoplite-dev; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=url="$SLACK_WEBHOOK_URL" --dry-run=client -o yaml | kubectl apply -f -

echo "==> kube-prometheus-stack (Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics)"
helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring \
  -f "$ROOT/monitoring/values/kube-prometheus-stack.yaml" $(v "${KPS_VERSION:-}") --wait --timeout 15m

echo "==> Traefik ingress controller"
helm upgrade --install traefik traefik/traefik -n traefik \
  -f "$ROOT/platform/traefik.yaml" $(v "${TRAEFIK_VERSION:-}") --wait

echo "==> Loki"
helm upgrade --install loki grafana/loki -n monitoring \
  -f "$ROOT/monitoring/values/loki.yaml" $(v "${LOKI_VERSION:-}") --wait --timeout 10m

echo "==> Tempo"
helm upgrade --install tempo grafana/tempo -n monitoring \
  -f "$ROOT/monitoring/values/tempo.yaml" $(v "${TEMPO_VERSION:-}") --wait

echo "==> Alloy (log collection)"
helm upgrade --install alloy grafana/alloy -n monitoring \
  -f "$ROOT/monitoring/values/alloy.yaml" $(v "${ALLOY_VERSION:-}") --wait

echo "==> ArgoCD"
helm upgrade --install argocd argo/argo-cd -n argocd \
  -f "$ROOT/platform/argocd.yaml" $(v "${ARGOCD_VERSION:-}") --wait --timeout 10m

echo
helm list -A
echo
echo "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
