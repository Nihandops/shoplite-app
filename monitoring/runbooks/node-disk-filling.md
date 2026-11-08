# Runbook: NodeDiskFilling (warning)

**Fires when:** a node filesystem is more than 85% full.

## Triage
1. Grafana → *Node Exporter / Nodes* dashboard → disk usage per mountpoint.
2. Usual suspects on kubeadm nodes: container images (`/var/lib/containerd`), local-path PVs (`/opt/local-path-provisioner`: Prometheus, Loki, Tempo, Postgres), journal logs.

## Actions
- `sudo crictl rmi --prune` (unused images) via SSM session.
- `sudo journalctl --vacuum-size=200M`.
- Reduce retention (Prometheus `retention`, Loki `retention_period`, Tempo `retention`) in Git.
- Grow the root volume in Terraform (`root_volume_gb`) and `growpart`/`resize2fs`.
