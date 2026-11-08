#!/usr/bin/env bash
# ShopLite end-to-end smoke test.
# Waits for /readyz, places an order, and polls until it is COMPLETED.
# Usage: scripts/smoke-test.sh [BASE_URL]   (default http://localhost:8080/api)
set -euo pipefail

BASE_URL="${1:-${BASE_URL:-http://localhost:8080/api}}"
READY_TIMEOUT="${READY_TIMEOUT:-120}"
ORDER_TIMEOUT="${ORDER_TIMEOUT:-60}"

log()  { printf '[smoke] %s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { log "FAIL: $*"; exit 1; }
command -v curl >/dev/null || fail "curl is required"

log "1/4 waiting for ${BASE_URL}/readyz (timeout ${READY_TIMEOUT}s)"
deadline=$((SECONDS + READY_TIMEOUT))
until curl -fsS "${BASE_URL}/readyz" >/dev/null 2>&1; do
  (( SECONDS < deadline )) || fail "service not ready after ${READY_TIMEOUT}s"
  sleep 2
done
log "ready"

log "2/4 listing products"
products=$(curl -fsS "${BASE_URL}/products") || fail "GET /products failed"
count=$(grep -o '"id":' <<<"$products" | wc -l)
(( count >= 10 )) || fail "expected >= 10 products, got ${count}"
log "found ${count} products"

log "3/4 placing an order"
resp=$(curl -sS -o /tmp/smoke-order.json -w '%{http_code}' -X POST "${BASE_URL}/orders" \
  -H 'Content-Type: application/json' -d '{"product_id": 1, "quantity": 2}') || fail "POST /orders failed"
[[ "$resp" == "201" ]] || fail "POST /orders returned HTTP ${resp}: $(cat /tmp/smoke-order.json)"
order_id=$(sed -E 's/.*"id":[[:space:]]*([0-9]+).*/\1/' /tmp/smoke-order.json)
[[ "$order_id" =~ ^[0-9]+$ ]] || fail "could not parse order id"
log "order ${order_id} created"

log "4/4 polling order ${order_id} until COMPLETED (timeout ${ORDER_TIMEOUT}s)"
deadline=$((SECONDS + ORDER_TIMEOUT))
while :; do
  status=$(curl -fsS "${BASE_URL}/orders/${order_id}" | sed -E 's/.*"status":[[:space:]]*"([A-Z]+)".*/\1/') || status="?"
  log "status=${status}"
  case "$status" in
    COMPLETED) break ;;
    FAILED)    fail "order ${order_id} FAILED" ;;
  esac
  (( SECONDS < deadline )) || fail "order not completed after ${ORDER_TIMEOUT}s"
  sleep 1
done

log "PASS - order ${order_id} COMPLETED"
