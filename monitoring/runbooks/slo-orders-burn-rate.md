# Runbook: OrdersSLOFastBurn / OrdersSLOSlowBurn

**SLO:** 99% of `POST /orders` complete in under 500 ms (30-day window, 1% error budget).

- **Fast burn** (14.4× over 1h and 5m): budget will be gone in ~2 days → page.
- **Slow burn** (6× over 6h and 30m): ticket.

Triage like HighLatency/HighErrorRate, scoped to route `/orders`. Use exemplars on the latency panel to jump to slow traces.
