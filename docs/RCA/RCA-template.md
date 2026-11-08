# Root Cause Analysis — ShopLite Chaos Day

| | |
|---|---|
| **Incident ID** | SHOP-INC-001 |
| **Date** | 2026-11-__ (Asia/Dhaka, UTC+6) |
| **Author** | Md Rasel |
| **Environment** | prod (namespace `shoplite`) |
| **Severity** | SEV-2 (customer-facing degradation) |
| **Status** | Resolved |

## 1. Summary (3–4 sentences)
_What users experienced, for how long, what caused it, how it was fixed._

## 2. Impact
- Duration of impact: `HH:MM → HH:MM` (__ min)
- Requests affected: __ % of `POST /orders` / p95 of `GET /products/{id}` = __ s / __ orders delayed
- Data loss: none / ...

## 3. Timeline (all times UTC+6)
| Time | Event | Evidence |
|---|---|---|
| HH:MM | Load test started (k6, 25 req/s, 15 min) | `evidence/01-k6-start.png` |
| HH:MM | Peer commit `xxxxxxx` "…" merged to shoplite-gitops, ArgoCD synced | ArgoCD history (looked at **after** RCA) |
| HH:MM | First symptom visible on Golden Signals: … | `evidence/02-dashboard.png` |
| HH:MM | Alert **<Name>** fired (severity …) — Slack notification | `evidence/03-slack-alert.png` |
| HH:MM | Investigation: dashboard → logs → trace | `evidence/04-…png` |
| HH:MM | Root cause identified | |
| HH:MM | `git revert` pushed to shoplite-gitops; ArgoCD sync | `evidence/07-revert.png` |
| HH:MM | Metrics back to baseline, alert resolved | `evidence/08-recovered.png` |

## 4. Detection
- **First alert:** `<AlertName>` (severity `<…>`), fired at HH:MM.
- **Why it triggered:** expression `<PromQL>` crossed `<threshold>` for `<for:>`. Value at fire time: `<…>`.
- Time from fault injection to alert (MTTD): __ min. _Why this long? (the `for:` window, rate window, …)_

## 5. Investigation (Grafana only)
1. **Dashboard** — which golden signal moved first, which route/pod, what did NOT change (rules out …). Screenshot.
2. **Metrics drill-down** — PromQL used, e.g. `histogram_quantile(0.95, sum by (le, route) (rate(http_request_duration_seconds_bucket{namespace="shoplite"}[5m])))`.
3. **Logs (Loki)** — query `{namespace="shoplite", app="…"} | json | level="ERROR"`; representative line with `trace_id`.
4. **Trace (Tempo)** — opened via exemplar / log `trace_id`; the span that explains the problem (name, duration, attributes), and the spans that are normal.
5. **Hypotheses considered and rejected** — e.g. "DB saturation: rejected because postgres spans are 3 ms".

## 6. Root cause
_One precise statement linking the change to the symptom, e.g. "Commit `abc123` set `orderWorker.chaos.slowDb: true` in `envs/prod/values.yaml`; every order then executed `pg_sleep(2)` before each of its two UPDATEs, raising processing time from ~1.5 s to ~5.5 s, which is below the arrival rate → queue backlog."_
Confirm only after writing sections 4–5: now inspect the Git diff and pod env to verify.

## 7. Recovery
- Action: `git revert <sha>` in shoplite-gitops → push → ArgoCD (manual Sync for prod) at HH:MM.
- Recovery time (revert → metrics normal) **MTTR**: __ min. Total incident duration: __ min.
- Verification: dashboard screenshot showing signal back to baseline; alert resolved message.

## 8. Preventive measure (at least one)
_e.g. Require a PR with review + CODEOWNERS on `envs/prod/`; a CI policy check (conftest/OPA) that fails if any `chaos.*` value is non-default in prod; canary rollout with automatic Prometheus analysis (Argo Rollouts)._

## 9. Lessons learned
- What went well:
- What went badly:
- Action items (owner, due date):
