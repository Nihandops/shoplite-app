# Runbook: QueueBacklog (warning)

**Fires when:** `order_queue_depth` > 50 for 10 minutes — orders are accepted faster than workers finish them.

## Triage
1. Golden Signals → *Orders created vs processed*: created > processed?
2. *Order processing time p95*: normal is 1–2 s. If it is ~5–6 s, each DB update is slow → open an exemplar trace and look at `UPDATE`/`SELECT pg_sleep` spans.
3. *Worker replicas (HPA)*: is the HPA at max? Are worker pods restarting (memory leak/OOM)?
4. Logs: `{namespace="shoplite", app="order-worker"} | json | level="ERROR"`.

## Common causes
- `CHAOS_SLOW_DB` → `pg_sleep(2)` before every update (trace shows 2 s DB spans).
- Workers crash-looping (see PodCrashLooping).
- Load spike beyond 4 replicas × concurrency.

## Recovery
Fix the root cause via Git revert; workers drain the backlog automatically (watch the queue panel fall to 0).
