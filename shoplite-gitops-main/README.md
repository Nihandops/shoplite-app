# shoplite-gitops

Desired state for ShopLite, reconciled by ArgoCD. **No pipeline runs `kubectl apply`.**

```
apps/        ArgoCD Applications (dev = auto-sync + self-heal, prod = manual sync, monitoring)
bootstrap/   root app-of-apps, applied once by hand
envs/dev/    values for namespace shoplite-dev  (http://<ALB>/dev/)
envs/prod/   values for namespace shoplite      (http://<ALB>/)
```

- CI in `shoplite-app` commits `image.tag` (short git SHA) to `envs/*/values.yaml`.
- Rollback = `git revert <commit>` here; ArgoCD syncs the previous state.
