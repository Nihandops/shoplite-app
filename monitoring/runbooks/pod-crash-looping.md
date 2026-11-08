# Runbook: PodCrashLooping (critical)

**Fires when:** a container's restart counter increased in the last 10 minutes.

## Triage
1. Golden Signals → *Container restarts* and *OOMKilled / last terminated reason*. `OOMKilled` → memory; `Error` → application crash.
2. *Memory working set per pod*: a saw-tooth that climbs steadily and drops at each restart = **memory leak**; compare with the 256Mi limit.
3. Logs of the previous container: Loki `{pod="<pod>"}` around the restart time; last lines before the gap.
4. If memory grows per processed order, check *Orders created vs processed* — leak proportional to throughput.

## Common causes
- `CHAOS_MEMORY_LEAK` in order-worker (~1 MiB retained per order → OOMKilled at 256Mi).
- Bad config/secret → app exits at start (logs show the exception).
- Failing liveness probe (slow start) → increase startupProbe.

## Recovery
Revert via Git; confirm restarts stop and memory is flat.
