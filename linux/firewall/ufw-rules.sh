#!/usr/bin/env bash
# Q3.4 — default deny inbound; allow only 22, 80, 443.
# KEEP A SECOND SSH SESSION OPEN while running this.
set -euo pipefail
sudo apt-get install -y ufw >/dev/null
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp  comment 'ssh'
sudo ufw allow 80/tcp  comment 'http'
sudo ufw allow 443/tcp comment 'https'
sudo ufw logging on
sudo ufw --force enable

echo "== evidence =="
sudo ufw status verbose
sudo ss -tulpn
