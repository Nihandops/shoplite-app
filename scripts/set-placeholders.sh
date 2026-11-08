#!/usr/bin/env bash
# Replaces YOUR_GITHUB_USER / YOUR_AWS_ACCOUNT_ID placeholders in both repos.
# Usage: scripts/set-placeholders.sh <github-user> <aws-account-id> [path-to-shoplite-gitops]
set -euo pipefail
GH="${1:?github user}"; ACCT="${2:?aws account id}"
APP="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${3:-$APP/../shoplite-gitops}"
for dir in "$APP" "$GITOPS"; do
  [ -d "$dir" ] || continue
  grep -rlE 'YOUR_GITHUB_USER|YOUR_AWS_ACCOUNT_ID' "$dir" --exclude-dir=.git --exclude=set-placeholders.sh \
    | xargs -r sed -i -e "s/YOUR_GITHUB_USER/${GH}/g" -e "s/YOUR_AWS_ACCOUNT_ID/${ACCT}/g"
done
echo "placeholders replaced"
