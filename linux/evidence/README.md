# Q3 evidence checklist

Put terminal screenshots (PNG) in this folder with these names:

| File | Command(s) shown |
|---|---|
| 01-users.png | `id deploy`, `getent group ops` |
| 02-sshd-effective.png | `sudo sshd -T \| grep -Ei 'permitrootlogin\|passwordauthentication'` |
| 03-root-refused.png | from your laptop: `ssh root@SERVER` → `Permission denied (publickey)` |
| 04-password-refused.png | `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password deploy@SERVER` → `Permission denied (publickey)` |
| 05-key-login-ok.png | `ssh -i key deploy@SERVER whoami` |
| 06-permissions.png | `ls -ld /var/log/shoplite`, `ls -l`, `getfacl /var/log/shoplite` |
| 07-backup-status.png | `systemctl status shoplite-backup.service` |
| 08-timers.png | `systemctl list-timers shoplite-backup.timer`, `ls -lh /var/backups/shoplite` |
| 09-ufw.png | `sudo ufw status verbose` |
| 10-ss.png | `sudo ss -tulpn` |
| 11-port-open.png | from another machine: `curl -I http://SERVER/` → 200 |
| 12-port-blocked.png | from another machine: `nc -vz -w3 SERVER 8000` (or 5432) → timed out |

**Why 777 is wrong (one line):** mode 777 lets every user and process on the host read, modify or delete the logs, which breaks least privilege and makes tampering and data leaks trivial.
