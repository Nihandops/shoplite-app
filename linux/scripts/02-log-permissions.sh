#!/usr/bin/env bash
# Q3.2 — /var/log/shoplite readable by the ops group only (chmod + chown + exactly ONE setfacl rule).
set -euo pipefail
sudo apt-get install -y acl >/dev/null
sudo mkdir -p /var/log/shoplite
sudo chown root:ops /var/log/shoplite
sudo chmod 2750 /var/log/shoplite          # rwx owner, r-x ops, nothing for others; setgid keeps group=ops
# the ONE ACL rule: default ACL so every NEW file inside is also readable by ops (and nobody else)
sudo setfacl -d -m g:ops:r-X /var/log/shoplite

# sample log so the inheritance is visible
echo '{"level":"INFO","service":"shoplite","message":"permission test"}' | sudo tee /var/log/shoplite/app.log >/dev/null

echo "== evidence =="
ls -ld /var/log/shoplite
sudo ls -l /var/log/shoplite
sudo getfacl /var/log/shoplite
sudo getfacl /var/log/shoplite/app.log
sudo -u deploy cat /var/log/shoplite/app.log && echo "deploy (ops) CAN read"
sudo -u nobody cat /var/log/shoplite/app.log 2>&1 || echo "nobody (not ops) CANNOT read"
# Why not 777? -> 777 lets EVERY local user/process read, modify or delete the logs (tampering, info leaks), violating least privilege.
