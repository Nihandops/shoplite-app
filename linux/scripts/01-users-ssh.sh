#!/usr/bin/env bash
# Q3.1 — deploy user, ops group, key-only SSH, no root login.
# Run as a sudo user WITH A SECOND SSH SESSION OPEN.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

sudo groupadd -f ops
id deploy >/dev/null 2>&1 || sudo useradd -m -s /bin/bash deploy
sudo usermod -aG ops deploy
sudo usermod -aG ops "${SUDO_USER:-$USER}"        # keep your admin user able to log in (AllowGroups)

# give deploy the same authorized key as the current user
sudo install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
sudo install -m 600 -o deploy -g deploy ~/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys

sudo install -m 644 "$REPO_DIR/sshd_config" /etc/ssh/sshd_config.d/99-shoplite-hardening.conf
# cloud images sometimes ship 50-cloud-init.conf with PasswordAuthentication yes — neutralise it
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
sudo sshd -t
sudo systemctl reload ssh || sudo systemctl reload sshd

echo "== evidence =="
id deploy
getent group ops
sudo sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication)'
