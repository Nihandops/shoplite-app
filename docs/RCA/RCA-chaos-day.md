# Root Cause Analysis — ShopLite Chaos Day

| | |
|---|---|
| **Incident ID** | SHOP-INC-001 |
| **Date** | 15 Nov 2026 (times in UTC; Dhaka = UTC+6) |
| **Author** | Nihandops |
| **Environment** | prod — namespace `shoplite`, served at `http://<ALB>/` |
| **Severity** | SEV-3 (degraded latency and errors, no data loss) |
| **Status** | Resolved |

## 1. Summary
On Chaos Day a fault flag (`orderWorker.chaos.memoryLeak: true`) was committed to `shoplite-gitops/envs/prod/values.yaml` twice, without the investigator looking at the diff (a peer was not available; the flag was picked at random by a script and hidden). Both times the change **never reached the cluster**, because the prod ArgoCD Application uses **manual sync** and the sync was not performed. Both commits were reverted through Git.

During the same window, prod showed a **real, unrelated degradation** under a 25 req/s k6 load: between **09:32 and 09:36** the HTTP 5xx ratio reached **18.7 %**, p95 latency rose to **~2 s on every route**, and the order queue grew to **126**. It recovered by 09:36 without any change. The evidence points to **capacity saturation of catalog-api and order-worker** at that load, not to the injected flag.

## 2. Impact
| Signal | Normal (09:04–09:24, 25 req/s) | Incident (09:32–09:36) |
|---|---|---|
| 5xx ratio | 0 – 0.2 % | 8.5 % → **18.7 %** → 8.2 % |
| p95 `POST /orders` | 0.44 – 0.92 s | 1.94 → **2.24 s** |
| p95 `GET /products` | 0.27 – 0.60 s | 1.41 → **2.09 s** |
| p95 `GET /products/{id}` | 0.28 – 0.64 s | 1.57 → **2.09 s** |
| `order_queue_depth` | 0 – 14 | 35 → **126** → 1 |
| Order processing p95 | 1.95 – 1.98 s | 1.97 – 1.98 s (unchanged) |
| Worker memory | 43 – 45.5 MB | 45.4 – 45.5 MB (flat) |
| Container restarts | 0 | 0 |

About 4 minutes of degraded service. No orders were lost: the queue drained back to 1 by 09:36.

## 3. Timeline (UTC)
| Time | Event | Source |
|---|---|---|
| 09:02 – 09:24 | Baseline under k6 load: 0 % errors, p95 < 1 s | Prometheus |
| 09:26 – 09:30 | No traffic (gap between load tests) | Prometheus (`nan`) |
| 09:32:11 | Chaos attempt 1: hidden flag committed to prod values; k6 load started | `/tmp/chaos-times.txt` |
| 09:32 | ArgoCD sync for prod returned `patched (no change)`, so **no rollout happened** | terminal |
| 09:32 – 09:36 | **Degradation**: 5xx up to 18.7 %, p95 ~2 s on all routes, queue up to 126 | Golden Signals / Prometheus |
| 09:32:29 | Attempt 1 reverted in Git (`git revert`) | git log |
| 09:35:17 | Chaos attempt 2: hidden flag committed again | `/tmp/chaos-times.txt` |
| 09:35:57 | `kubectl get pods`: catalog-api and order-worker still **110 min old**, so the flag was **not live** | terminal |
| 09:36 | Metrics back to baseline (5xx falling, queue 1) | Prometheus |
| 09:37:42 | Attempt 2 reverted in Git | git log |

## 4. Detection
- **No ShopLite alert fired.** `ALERTS{alertstate="firing"}` shows only `Watchdog`, `InfoInhibitor` and an earlier `OrdersSLOSlowBurn` (08:52–08:56).
- **Why not:** `HighErrorRate` needs > 5 % for **5 minutes** and `HighLatency` needs p95 > 1 s for **5 minutes**. The degradation lasted about 4 minutes, so it stayed under both `for:` windows. `QueueBacklog` needs > 50 for 10 minutes; the queue was above 50 for only about 2 minutes.
- **How it was seen:** on the **ShopLite — Golden Signals** dashboard (5xx stat panel, latency-per-route panel, queue-depth panel).
- **Lesson:** short, sharp incidents are invisible to 5-minute alerts. The `OrdersSLOFastBurn` rule (5 m + 1 h windows) is the right tool; it did not fire because the 1 h window diluted the 4-minute spike.

## 5. Investigation (Grafana only)
1. **Dashboard:** errors and latency rose on **all routes at once**, including read-only `GET /products`, which never touches Redis or the worker. A worker-only fault (memory leak, slow DB) cannot explain slow product reads, so the API layer itself was struggling.
2. **Worker signals ruled out the injected flag:** worker memory stayed flat at ~45 MB (a leak adds ~1 MB per order) and there were **0 restarts** (a leak at 256 Mi would cause OOMKills). Processing p95 stayed at ~1.97 s, which matches the normal 1–2 s simulated work, so `CHAOS_SLOW_DB` was not active either.
3. **Queue:** depth rose to 126 while processing time stayed normal, meaning orders **arrived faster than one worker pod could finish them**. One worker × 4 threads ÷ ~1.5 s ≈ 2.7 orders/s, and 10 % of 25 req/s = 2.5 orders/s, so the worker runs at about 95 % of capacity. Any burst overflows it.
4. **Configuration check (after writing sections 4–5):** both prod pods were 110 minutes old, and the flag existed only in Git. ArgoCD showed prod **OutOfSync** with no completed operation.

## 6. Root cause
**Primary (the observed degradation):** under-provisioned capacity for a 25 req/s mixed load. catalog-api has a 500m CPU limit with 2 replicas, and order-worker has 1 replica at 4 threads (~2.7 orders/s) against ~2.5 orders/s of demand. A burst at the start of the 09:32 load test saturated both, which produced timeouts (5xx), ~2 s latency on every route and a queue backlog. The HPA scales the worker on **CPU**, but the worker mostly sleeps (I/O-bound), so CPU stayed low and **the HPA did not scale out**.

**Secondary (the chaos exercise itself):** the injected `memoryLeak` flag never took effect because **prod requires a manual ArgoCD sync** and the sync step was skipped. The `kubectl patch … operation` call returned `no change` and the UI Sync was not pressed. The GitOps safety gate worked as designed: a bad commit to prod values cannot go live on its own.

## 7. Recovery
- Both fault commits were reverted with `git revert` in `shoplite-gitops` (09:32:29 and 09:37:42), restoring the desired state in Git.
- The capacity degradation recovered on its own once the burst passed (about 4 min, 09:32 → 09:36).
- **Time to recover:** about 4 minutes of degradation; both fault commits were reverted within 2.5 minutes of being committed.

## 8. Preventive measures
1. **Scale the worker on queue depth, not CPU:** use KEDA (Redis list length) or an HPA on the external metric `order_queue_depth` (target 20 per pod).
2. **Raise baseline capacity:** order-worker `minReplicas: 2` in prod and catalog-api CPU limit 1 core; re-run k6 at 25 req/s to confirm p95 < 1 s and 0 % 5xx.
3. **Faster alerting for short incidents:** rely on the multi-window SLO burn-rate alerts, and add a 1-minute *page* rule for 5xx > 15 %.
4. **Make "is it live?" visible:** add an ArgoCD `OutOfSync` notification for `shoplite-prod`, and a dashboard panel with the running image tag and config checksum, so a committed-but-not-synced change is obvious.

## 9. Lessons learned
- **Went well:** the Golden Signals dashboard showed the problem immediately, and the worker panels (memory, restarts, processing time) quickly ruled out the injected flag. Git revert was fast and auditable.
- **Went badly:** the chaos procedure skipped the prod sync step, so the planned fault was never exercised. Alerts with 5-minute `for:` windows missed a 4-minute incident.
- **Follow-up:** repeat Chaos Day with the sync step checked (pods restarted, AGE < 2 min) and at least 12 minutes of observation, so the injected fault itself is detected and analysed.

