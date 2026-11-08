#!/usr/bin/env bash
# Q3.3 — install the systemd backup service + timer
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
sudo install -m 750 -o root -g ops "$REPO_DIR/scripts/shoplite-backup.sh" /usr/local/bin/shoplite-backup.sh
sudo install -d -m 750 -o root -g ops /var/backups/shoplite
sudo install -m 644 "$REPO_DIR/systemd/shoplite-backup.service" /etc/systemd/system/
sudo install -m 644 "$REPO_DIR/systemd/shoplite-backup.timer"   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now shoplite-backup.timer
sudo systemctl start shoplite-backup.service   # run once now to prove it works

echo "== evidence =="
systemctl status shoplite-backup.service --no-pager || true
systemctl list-timers shoplite-backup.timer --no-pager
sudo ls -lh /var/backups/shoplite/
journalctl -u shoplite-backup.service -n 5 --no-pager
