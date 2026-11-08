# ShopLite — Step-by-step runbook (from zero to submission)

Every command below is meant to be pasted into a terminal. On Windows, use **WSL2 Ubuntu 22.04/24.04**
(Ansible does not run natively on Windows). Commands marked **(server)** run on a remote machine; everything
else runs in your WSL terminal.

> Placeholders you will replace once: `Nihandops`, `396608798769`. Script: `scripts/set-placeholders.sh`.

**Suggested schedule (deadline 17 Nov):**
Day 1 local app (Q1–Q2) · Day 2 Linux server (Q3) · Day 3 Terraform + Ansible (Q4) · Day 4 platform + Helm (Q5) ·
Day 5–6 observability (Q6) · Day 7 CI/CD + GitOps (Q7) · Day 8 Chaos day + RCA (Q8) · Day 9 evidence, rehearsal · Day 10 buffer, `terraform destroy`.
Destroy the AWS stack at night (`terraform destroy`) and re-create it the next day — it is fully reproducible, and it keeps you under the USD 20 budget.

---

## 0. One-time tool setup (WSL Ubuntu)

```bash
# basics
sudo apt-get update && sudo apt-get install -y git make jq unzip curl python3-pip python3-venv pipx shellcheck
# Docker: install Docker Desktop on Windows and enable "WSL integration" for your Ubuntu distro, then:
docker version && docker compose version

# AWS CLI v2 + Session Manager plugin
curl -sSLo /tmp/awscli.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip && unzip -q /tmp/awscli.zip -d /tmp && sudo /tmp/aws/install
curl -sSLo /tmp/ssm.deb https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb && sudo dpkg -i /tmp/ssm.deb

# Terraform
wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# Ansible, kubectl, helm, k6, yq
pipx install --include-deps ansible && pipx ensurepath && exec $SHELL
curl -sSLo /tmp/kubectl "https://dl.k8s.io/release/v1.33.0/bin/linux/amd64/kubectl" && sudo install /tmp/kubectl /usr/local/bin/
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
sudo gpg -k; sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install -y k6
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq

# SSH key used for every server in this project
ssh-keygen -t ed25519 -f ~/.ssh/shoplite -N "" -C "shoplite"
```

## 1. Put the code on GitHub

1. On github.com create two **public** repositories (no README): `shoplite-app` and `shoplite-gitops`.
   (Public keeps ArgoCD simple — no repo credentials. Nothing secret is ever committed.)
2. Unzip the two folders you downloaded into `~/work/` and push:

```bash
mkdir -p ~/work && cd ~/work
unzip ~/Downloads/shoplite-app.zip && unzip ~/Downloads/shoplite-gitops.zip   # adjust path (/mnt/c/Users/<you>/Downloads)
cd shoplite-app
aws sts get-caller-identity --query Account --output text   # after step 4.1; or fill the account id now
./scripts/set-placeholders.sh Nihandops 396608798769 ../shoplite-gitops
git add -A && git commit -m "ShopLite capstone: initial import"
git remote add origin git@github.com:Nihandops/shoplite-app.git && git push -u origin main
cd ../shoplite-gitops
git add -A && git commit -m "GitOps: ArgoCD apps and env values"
git remote add origin git@github.com:Nihandops/shoplite-gitops.git && git push -u origin main
```
(If you use HTTPS instead of SSH remotes, use `https://github.com/Nihandops/<repo>.git`.)

---

## 2. Q1 + Q2 — app and containers (local)

```bash
cd ~/work/shoplite-app
make test                     # 13 API tests + 5 worker tests run inside Docker
make up                       # builds 3 images, starts 5 containers, waits for healthy
make smoke                    # readyz -> list -> order -> poll until COMPLETED
docker images | grep shoplite # every image must be < 150 MB
docker compose ps             # all "healthy"
docker compose exec catalog-api id      # uid=10001 -> non-root
docker compose logs catalog-api | head  # JSON logs with timestamp, level, service, message, trace_id
```
Browser: http://localhost:8080 → order a product → status goes PENDING → PROCESSING → COMPLETED.

Graceful shutdown proof: `docker compose stop order-worker && docker compose logs order-worker | tail -5`
(shows `received signal 15; finishing in-flight orders` … `stopped cleanly`).

Chaos flags proof (optional screenshot):
```bash
CHAOS_ERROR_RATE=0.5 docker compose up -d catalog-api
for i in $(seq 10); do curl -s -o /dev/null -w '%{http_code} ' -X POST localhost:8080/api/orders -H 'Content-Type: application/json' -d '{"product_id":1,"quantity":1}'; done; echo
docker compose up -d catalog-api    # back to default (0)
```
**Checkpoint:** `make down && make clean && make up && make smoke` must end with `PASS`. Screenshot it.

---

## 3. Q3 — Linux server administration

### 3.1 Create the server (cheap EC2, destroy afterwards)
```bash
cd ~/work/shoplite-app/terraform/linux-server
terraform init
terraform apply -var "my_ip_cidr=$(curl -s https://checkip.amazonaws.com)/32"
ssh -i ~/.ssh/shoplite ubuntu@$(terraform output -raw public_ip)
```
(A local Ubuntu VM works too; then skip Terraform and SSH into the VM.)

### 3.2 On the server **(server)**
```bash
sudo git clone https://github.com/Nihandops/shoplite-app.git /opt/shoplite-app
sudo chown -R ubuntu:ubuntu /opt/shoplite-app && cd /opt/shoplite-app
sudo docker compose -f docker-compose.yml -f linux/docker-compose.server.yml up -d --build --wait
sudo docker compose ps
```
**Open a SECOND SSH session now and keep it open** until 3.5 is done.

```bash
cd /opt/shoplite-app
./linux/scripts/01-users-ssh.sh          # deploy user, ops group, sshd drop-in, reload
./linux/scripts/02-log-permissions.sh     # chown/chmod/one setfacl, ls -l, getfacl
./linux/scripts/03-backup-timer.sh        # service + timer, runs one backup now
./linux/firewall/ufw-rules.sh             # deny incoming, allow 22/80/443, ss -tulpn
```

### 3.3 Prove it (from WSL / another machine)
```bash
IP=<server public ip>
ssh -i ~/.ssh/shoplite root@$IP                                   # -> Permission denied (publickey)
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password deploy@$IP   # -> Permission denied (publickey)
ssh -i ~/.ssh/shoplite deploy@$IP whoami                          # -> deploy
curl -sI http://$IP/ | head -1                                    # -> HTTP/1.1 200 OK   (open port)
nc -vz -w3 $IP 8000; nc -vz -w3 $IP 5432                          # -> timed out        (blocked by UFW — the AWS SG allows them!)
```
Take the 12 screenshots listed in `linux/evidence/README.md`, save them into `linux/evidence/`, commit.
Then `terraform destroy -var "my_ip_cidr=0.0.0.0/32"` in `terraform/linux-server`.

---

## 4. Q4 — AWS infrastructure (Terraform) and cluster (Ansible)

### 4.1 AWS credentials
Create an IAM user (or SSO) with AdministratorAccess **for Terraform on your laptop only**, then:
```bash
aws configure            # region: ap-southeast-1, output: json
aws sts get-caller-identity
```

### 4.2 Bootstrap (state bucket, lock table, USD 20 budget, GitHub OIDC role) — once
```bash
cd ~/work/shoplite-app/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars && nano terraform.tfvars     # your email + GitHub user
terraform init && terraform apply
terraform output     # note: state_bucket, github_actions_role_arn
```
> Confirm the AWS Budgets email subscription if AWS sends one. If an OIDC provider for GitHub already exists in your account:
> `terraform import aws_iam_openid_connect_provider.github arn:aws:iam::<ACCOUNT>:oidc-provider/token.actions.githubusercontent.com`

### 4.3 Main stack (VPC, NAT, SGs, 3 EC2 in private subnets, ALB, ECR)
```bash
cd ~/work/shoplite-app/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config="bucket=$(terraform -chdir=bootstrap output -raw state_bucket)"
terraform fmt -recursive && terraform validate
terraform plan -out tfplan && terraform apply tfplan          # ~5 min
terraform output
aws ec2 describe-instances --filters Name=tag:project,Values=shoplite --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,PrivateIpAddress,PublicIpAddress]' --output table
```
Evidence: `terraform output`, the table above (no public IPs on nodes), `aws s3 ls s3://<state_bucket>/shoplite/`
(state + `.tflock` while a plan runs), and the budget: `aws budgets describe-budgets --account-id <ACCOUNT>`.

### 4.4 Ansible: harden nodes, containerd, kubeadm, join, kubeconfig
Terraform wrote `ansible/inventory/hosts.ini` (SSH is tunnelled through **SSM**; port 22 is closed in AWS).
```bash
cd ~/work/shoplite-app/ansible
ansible-galaxy collection install -r requirements.yml
sleep 60    # give the SSM agent a minute after first boot
ansible all -m ping
ansible-playbook site.yml               # ~10 min
ansible-playbook site.yml               # run again: should be all ok / changed=0  -> idempotent (screenshot)
```

### 4.5 Reach the private API server from your laptop
Terminal tab 1 (leave running):
```bash
cd ~/work/shoplite-app && ./scripts/tunnel.sh
```
Terminal tab 2:
```bash
export KUBECONFIG=~/work/shoplite-app/ansible/kubeconfig
kubectl get nodes -o wide        # 1 control-plane + 2 workers, Ready, INTERNAL-IP 10.0.10.x/11.x
```
Add `export KUBECONFIG=~/work/shoplite-app/ansible/kubeconfig` to `~/.bashrc`.

---

## 5. Platform add-ons (storage, metrics-server, Traefik, observability, ArgoCD)

Create a Slack incoming webhook (api.slack.com → *Create App* → *Incoming Webhooks* → channel `#shoplite-alerts`).
No Slack? Use a free https://webhook.site URL temporarily — but then change the receiver in
`monitoring/values/kube-prometheus-stack.yaml` from `slack_configs` to `webhook_configs: [{url_file: ...}]`.

```bash
cd ~/work/shoplite-app
export GRAFANA_ADMIN_PASSWORD='choose-a-strong-one'
export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/XXX/YYY/ZZZ'
./scripts/install-platform.sh           # ~10-15 min; prints `helm list -A` and the ArgoCD admin password
kubectl get pods -A
curl -s -o /dev/null -w '%{http_code}\n' http://$(terraform -chdir=terraform output -raw alb_dns_name)/   # 404 from Traefik = ALB->ingress path works
```
Record the chart versions from `helm list -A` in your report (reproducibility).

---

## 6. Q7 part 1 — connect GitHub Actions (OIDC) and build the first images

In **shoplite-app** → Settings → *Secrets and variables* → *Actions*:

| Type | Name | Value |
|---|---|---|
| Variable | `AWS_ROLE_ARN` | `terraform -chdir=terraform/bootstrap output -raw github_actions_role_arn` |
| Variable | `TF_STATE_BUCKET` | `terraform -chdir=terraform/bootstrap output -raw state_bucket` |
| Variable | `SSH_PUBLIC_KEY` | `cat ~/.ssh/shoplite.pub` |
| Secret | `GITOPS_TOKEN` | fine-grained PAT → *Only select repositories: shoplite-gitops* → *Contents: Read and write* |

Trigger the pipeline:
```bash
cd ~/work/shoplite-app && git commit --allow-empty -m "ci: first build" && git push
```
Actions tab: `lint → test → build (x3: build, size check, Trivy, push) → update-gitops` all green.
Check: `aws ecr list-images --repository-name shoplite/catalog-api` and a new commit in shoplite-gitops
(`deploy: shoplite <sha>`). No AWS keys are stored in GitHub — only the role ARN.

---

## 7. Q5 — deploy with ArgoCD

```bash
# DB credentials: created out-of-band with a random password, never in Git
./scripts/create-db-secret.sh shoplite
./scripts/create-db-secret.sh shoplite-dev

# bootstrap the app-of-apps ONCE (cluster bootstrap by a human, not the pipeline)
kubectl apply -n argocd -f ~/work/shoplite-gitops/bootstrap/root-app.yaml

# ArgoCD UI
kubectl -n argocd port-forward svc/argocd-server 8081:80      # http://localhost:8081  user: admin
```
- `shoplite-dev` syncs automatically. `shoplite-prod` shows **OutOfSync** → click **SYNC** (manual by design).
- `shoplite-monitoring` syncs the dashboard ConfigMap and alert rules.

Verify:
```bash
kubectl -n shoplite get pods,svc,ingress,hpa,pdb,netpol,pvc
kubectl -n shoplite get pods -o jsonpath='{range .items[*]}{.metadata.name}{"  uid="}{.spec.securityContext.runAsUser}{"\n"}{end}'
kubectl -n shoplite get deploy -o custom-columns=NAME:.metadata.name,REQ:.spec.template.spec.containers[0].resources.requests,LIM:.spec.template.spec.containers[0].resources.limits
# NetworkPolicy proof: web cannot reach postgres, catalog-api can
kubectl -n shoplite exec deploy/web -- sh -c 'nc -zv -w3 postgres 5432' ; echo "exit=$?  (expect failure)"
kubectl -n shoplite exec deploy/catalog-api -- python -c "import socket;socket.create_connection(('postgres',5432),3);print('catalog-api -> postgres OK')"
```
**Checkpoint (Q5):** open `http://<alb_dns_name>/` in the browser, place an order, watch it reach **COMPLETED**. Screenshot with the URL bar visible.
Dev is at `http://<alb_dns_name>/dev/`.

---

## 8. Q6 — observability

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80      # http://localhost:3000  admin / $GRAFANA_ADMIN_PASSWORD
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090  # targets page: http://localhost:9090/targets
```
1. Prometheus → *Status → Targets*: `serviceMonitor/shoplite/catalog-api`, `…/order-worker`, node-exporter, kube-state-metrics all **UP**.
2. Generate traffic: `k6 run -e BASE_URL=http://<alb_dns_name> -e DURATION=10m loadtest/k6-shoplite.js`
3. Grafana → Dashboards → **ShopLite — Golden Signals** (env = `shoplite`): p50/p95/p99 per route, RPS, 5xx rate,
   CPU/memory per pod, queue depth, worker replicas, created vs processed.
4. **Correlation demo (the "under 2 minutes" path):**
   - latency panel → hover a ◆ exemplar → *Query with Tempo* → full trace
     `POST /orders` (catalog-api) → `INSERT` (postgres) → `orders:pending publish` (redis) → `orders:pending process` (order-worker) → `UPDATE` ×2.
   - In the trace click **Logs for this span** → Loki lines of both services with the same `trace_id`.
   - In Loki (Explore): `{namespace="shoplite"} | json | level="ERROR"` → expand a line → **Open trace in Tempo**.
5. Alerts: Grafana → Alerting → *Alert rules* (or Prometheus `/alerts`) shows HighErrorRate, HighLatency, QueueBacklog,
   PodCrashLooping, NodeDiskFilling with `severity` + `runbook_url`. To test Slack delivery, set
   `catalogApi.chaos.errorRate: 0.3` in `shoplite-gitops/envs/dev/values.yaml`, push, run k6 against `/dev`, wait ~6 min → Slack message; then revert.

Screenshots: targets, dashboard under load, exemplar → trace, trace → logs, log → trace, alert list, Slack message.

---

## 9. Q7 part 2 — checkpoints

**Code change reaches the browser with no manual deploy command**
```bash
cd ~/work/shoplite-app
sed -i 's#<title>ShopLite</title>#<title>ShopLite — v2</title>#; s#<h1>ShopLite</h1>#<h1>ShopLite v2</h1>#' services/web/public/index.html
git commit -am "feat(web): new page title" && git push
```
Watch: Actions run → gitops commit → ArgoCD `shoplite-dev` auto-syncs → refresh `http://<alb>/dev/` → "ShopLite v2" and
the header shows the new build SHA. (Prod gets it after you press Sync — that is the production gate.)

**Self-healing**
```bash
kubectl -n shoplite-dev scale deploy/web --replicas=4           # manual drift
kubectl -n shoplite-dev get deploy web -w                        # ArgoCD puts it back to 1 within seconds
kubectl -n shoplite-dev edit configmap shoplite-config           # change LOG_LEVEL -> reverted too
```
Screenshot ArgoCD *History and rollback / Events* showing the self-heal.

**PR pipeline + Terraform plan comment**
```bash
git checkout -b tf-tags && sed -i 's/managed-by = "terraform"/managed-by = "terraform"\n      owner      = "rasel"/' terraform/versions.tf
terraform -chdir=terraform fmt && git commit -am "chore(tf): owner tag" && git push -u origin tf-tags
```
Open a PR → `ci` runs lint/test/build/Trivy (no push) and `terraform-plan` posts the plan as a comment. Screenshot, then merge or close.

---

## 10. Q8 — Chaos day and RCA

Follow `docs/RCA/chaos-day-procedure.md`, write `docs/RCA/RCA-chaos-day.md` from `docs/RCA/RCA-template.md`.
What each fault looks like (use to reason, not to guess):

| Flag | First signal | Alert | Proof in Grafana |
|---|---|---|---|
| `CHAOS_ERROR_RATE` | 5xx on `POST /orders` only | HighErrorRate | ERROR logs "order creation failed"; trace has `chaos.injected_error=true` and no DB/Redis child spans |
| `CHAOS_LATENCY_MS` | p95/p99 of `/products/{product_id}` up, p50 flat | HighLatency | exemplar trace with a long `chaos.latency` span |
| `CHAOS_SLOW_DB` | processing p95 ~5–6 s, created > processed, queue rising | QueueBacklog | worker trace: `SELECT pg_sleep` 2 s spans before each UPDATE |
| `CHAOS_MEMORY_LEAK` | worker memory climbs in a saw-tooth, restarts | PodCrashLooping | last terminated reason `OOMKilled`; memory slope tracks orders processed |

Recovery is always: `git revert <sha> && git push` in shoplite-gitops → ArgoCD Sync → dashboard back to baseline.

---

## 11. Bonus (only after Q1–Q8)
- **Bonus 4 (SLO + burn-rate)** is already in `monitoring/alert-rules/shoplite-alerts.yaml` (`OrdersSLOFastBurn`, `OrdersSLOSlowBurn`). Show them in Prometheus `/alerts` and explain the 14.4×/6× windows.
- Bonus 3 (Argo Rollouts canary), 1 (EKS), 2 (SQS + Lambda) are not included.

---

## 12. Live demo (10 min) script
1. Architecture diagram (`docs/architecture-diagram/architecture.png`) — 2 min.
2. Push a title change → Actions → gitops commit → ArgoCD dev sync → browser — 3 min (start it first, talk while it runs).
3. Golden Signals under k6 load — 2 min.
4. Exemplar → trace → *Logs for this span* — 1 min.
5. `kubectl scale` drift → ArgoCD reverts — 1 min.

## 13. Submission checklist
- [ ] Both repo URLs (public) in the Google Form
- [ ] `linux/evidence/*.png`, `docs/RCA/RCA-chaos-day.md` (+ evidence screenshots), checkpoint screenshots in `docs/evidence/`
- [ ] `helm list -A` versions noted, ArgoCD screenshots, CI run links
- [ ] Nothing secret in Git: `git log -p | grep -iE 'password|secret|AKIA'` returns nothing sensitive

## 14. Cost guard / cleanup
```bash
kubectl delete -n argocd -f ~/work/shoplite-gitops/bootstrap/root-app.yaml   # optional
cd ~/work/shoplite-app/terraform && terraform destroy                          # nightly + after grading
cd bootstrap && terraform destroy                                              # ONLY at the very end (removes state bucket + budget)
```
Rough cost while running (ap-southeast-1): 2×t3.large + 1×t3.medium + NAT + ALB ≈ USD 0.35/hour. Destroying when you stop
for the day keeps the whole project around USD 10–15.

## Troubleshooting
| Symptom | Fix |
|---|---|
| `ansible all -m ping` hangs | `aws ssm describe-instance-information` — wait until all 3 are Online; check session-manager-plugin is installed |
| `kubectl` "connection refused 127.0.0.1:6443" | `scripts/tunnel.sh` is not running |
| Pods `ImagePullBackOff` from ECR | first CI run hasn't pushed yet (`image.tag: initial`), or ecr-credential-provider failed: `journalctl -u kubelet | grep credential` on the node (via `aws ssm start-session`) |
| ArgoCD app `Unknown`/repo error | repos must be public, or add them in ArgoCD → Settings → Repositories |
| Postgres `CrashLoopBackOff` permission denied | `kubectl -n shoplite delete pvc data-postgres-0` once and resync (local-path dir created with wrong owner) |
| ALB targets unhealthy | Traefik pods running? `kubectl -n traefik get svc` shows NodePort 30080? |
| Grafana dashboard empty | env dropdown = `shoplite`; Prometheus targets UP; generate traffic |
