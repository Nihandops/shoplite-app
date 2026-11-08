#!/usr/bin/env bash
# Fallback load generator if k6 is not installed (needs only curl + xargs).
# Usage: loadtest/load.sh http://<ALB DNS> [seconds=900] [rps=25]
set -uo pipefail
BASE="${1:?base url}/api"; DUR="${2:-900}"; RPS="${3:-25}"
end=$((SECONDS + DUR))
while (( SECONDS < end )); do
  for _ in $(seq "$RPS"); do
    r=$((RANDOM % 10))
    if (( r == 0 )); then
      curl -s -o /dev/null -X POST "$BASE/orders" -H 'Content-Type: application/json' \
        -d "{\"product_id\": $((RANDOM % 10 + 1)), \"quantity\": 1}" &
    else
      curl -s -o /dev/null "$BASE/products/$((RANDOM % 10 + 1))" &
    fi
  done
  sleep 1
done
wait
