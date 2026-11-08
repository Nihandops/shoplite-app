# Runbook: HighErrorRate (critical)

**Fires when:** more than 5% of HTTP requests in a ShopLite namespace return 5xx for 5 minutes.

## Triage (Grafana only, < 2 min)
1. Open **ShopLite — Golden Signals** (link in the alert) → *HTTP 5xx error rate by route*. Which route? (`POST /orders` vs everything)
2. *Logs* row → filter `level=ERROR`. Read the `message` field; click the **trace_id** → Tempo.
3. In the trace: is the error raised inside `catalog-api` before any DB/Redis span (application logic / injected fault), or does a `postgres`/`redis` child span carry the error (dependency)?
4. Check *Requests per second* — did traffic change? Check ArgoCD/Git for a deploy at the start time (annotations on the dashboard).

## Common causes
| Evidence | Likely cause | Action |
|---|---|---|
| Only `POST /orders`, no DB/Redis error spans, span attribute `chaos.injected_error=true` | `CHAOS_ERROR_RATE` set in values | Revert the Git commit, let ArgoCD sync |
| `redis` spans fail, `/readyz` 503 | Redis down / NetworkPolicy | `kubectl -n <ns> get pods,netpol` |
| `postgres` spans fail | DB down / credentials | check StatefulSet, Secret |
| started right after a deploy | bad release | `git revert` in shoplite-gitops |

## Recovery
Revert the offending commit in **shoplite-gitops**; ArgoCD syncs (prod: press *Sync*). Confirm the 5xx panel returns to 0 and the alert resolves.
