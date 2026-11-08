# Chaos Day — procedure and evidence checklist

1. **Before** (you): dashboards green, alerts quiet. Screenshot the Golden Signals dashboard (baseline).
2. Grant the peer **Write** on `shoplite-gitops` (GitHub → Settings → Collaborators) for 1 hour.
3. Peer edits **one** flag in `envs/prod/values.yaml`, e.g.
   ```yaml
   catalogApi:
     chaos:
       errorRate: 0.2      # or latencyMs: 1500
   orderWorker:
     chaos:
       memoryLeak: true    # or slowDb: true
   ```
   and commits with an innocuous message ("chore: tidy values"). Prod is manual-sync: the peer (or you, without looking at the diff) presses **SYNC** on `shoplite-prod` in ArgoCD.
4. Start the load test (15 min, ≥ 20 req/s) and note the start time:
   ```bash
   k6 run -e BASE_URL=http://<ALB_DNS> -e RATE=25 -e DURATION=15m loadtest/k6-shoplite.js
   ```
5. Investigate **only** in Grafana (Golden Signals → Explore Loki → Tempo). Do not run `git log/diff`, `kubectl describe`, or look at env vars.
6. Take timestamped screenshots (Windows: Win+Shift+S; keep the clock visible) of: dashboard, alert in Slack, Alertmanager/Grafana alert list, Loki query, Tempo trace, revert commit, ArgoCD sync, recovered dashboard.
7. Write the RCA (sections 1–5) **before** confirming with Git.
8. Recover: `git revert <sha> && git push` in shoplite-gitops → ArgoCD Sync → watch the dashboard return to normal and the alert resolve.
9. Fill sections 6–9 of the RCA, save it as `docs/RCA/RCA-chaos-day.md` (+ PDF), commit screenshots under `docs/RCA/evidence/`.
