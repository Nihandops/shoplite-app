#!/usr/bin/env bash
# Creates the PostgreSQL credentials Secret for one namespace with a random password.
# Idempotent: an existing secret is left untouched (so the DB password never changes under a running DB).
set -euo pipefail
NS="${1:?usage: create-db-secret.sh <namespace>}"
if kubectl -n "$NS" get secret shoplite-db >/dev/null 2>&1; then
  echo "secret shoplite-db already exists in $NS — leaving it"
  exit 0
fi
PASS="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)"
kubectl -n "$NS" create secret generic shoplite-db \
  --from-literal=username=shoplite --from-literal=password="$PASS"
echo "created secret shoplite-db in $NS"
