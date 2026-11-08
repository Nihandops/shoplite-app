# Runbook: HighLatency (warning)

**Fires when:** p95 latency of any route is above 1 s for 5 minutes.

## Triage
1. Golden Signals → *Latency p50/p95/p99 per route*. Which route? Is p50 normal while p95/p99 is high (a fraction of requests slow) or is everything slow?
2. Click an **exemplar** (◆) on the slow series → opens the exact slow trace in Tempo.
3. In the trace find the longest span: `chaos.latency` span → injected latency; long `SELECT` span → DB; nothing but the handler → CPU throttling (check *CPU per pod* vs limits).
4. Correlate logs: from the trace, *Logs for this span* → Loki.

## Common causes
- `CHAOS_LATENCY_MS` enabled (≈30% of `GET /products/{id}` slow → p50 fine, p95/p99 high).
- CPU throttling at the 500m limit under load → scale replicas / raise limits.
- Slow DB queries / pool exhaustion.

## Recovery
Revert the change via Git (ArgoCD) or scale out; verify p95 < 1 s on the dashboard.
