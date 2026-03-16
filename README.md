# ESMOS Healthcare DevSecOps Platform

A Service Management platform for Healthcare, deploying **Odoo** (ERP/Operations), **Moodle** (LMS/Training), and a **compliant Helpdesk** on **Google Kubernetes Engine** using an ITIL 4.0 DevSecOps approach.

## Architecture

### CI/CD Flow

```
GitHub Actions (CI/CD)
    │
    ├── PR opened ──→ terraform plan (RFC review)
    └── PR merged ──→ terraform apply
                          │
                          ├── GKE Cluster (1-3 nodes, e2-medium, private)
                          ├── Cloud SQL PostgreSQL (private IP, daily backups)
                          ├── VPC (subnets: gke, db, ingress + private service access)
                          ├── ArgoCD (GitOps controller)
                          │     ├── Syncs → Odoo (official image, from Git)
                          │     └── Syncs → Moodle (official image, from Git)
                          └── Prometheus + Grafana (live monitoring)
```

### Infrastructure Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  GCP Project: esmos-healthcare        Region: asia-southeast1 (Singapore)    │
│                                                                              │
│  ┌─── GCS Bucket (outside VPC) ──────────────────────────────────────────┐   │
│  │  gs://esmos-healthcare-tfstate                                        │   │
│  │  ├── terraform/state/    (Terraform state)                            │   │
│  │  └── moodle-backups/     (Daily MariaDB dumps, 7-day retention)       │   │
│  └───────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─── VPC: esmos-healthcare-vpc (10.0.0.0/16) ──────────────────────────┐    │
│  │                                                                      │    │
│  │  ┌─── gke-subnet (10.0.1.0/24) ── PRIVATE ────────────────────────┐  │    │
│  │  │  Pods: 10.10.0.0/16    Services: 10.20.0.0/16                  │  │    │
│  │  │                                                                │  │    │
│  │  │  ┌─── GKE Node 1 (e2-medium: 2 vCPU, 4GB) ── No Public IP ──┐  │  │    │
│  │  │  │                                                          │  │  │    │
│  │  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │  │  │    │
│  │  │  │  │ Odoo Pod    │  │ Moodle Pod  │  │ Moodle Pod #2   │   │  │  │    │
│  │  │  │  │ (1 replica) │  │ (1 replica) │  │ (HPA scaled)    │   │  │  │    │
│  │  │  │  │ Port: 8069  │  │ Port: 8080  │  │ (when CPU >70%) │   │  │  │    │
│  │  │  │  └──────┬──────┘  └──────┬──────┘  └─────────────────┘   │  │  │    │
│  │  │  │         │                │                               │  │  │    │
│  │  │  │         │         ┌──────┴──────────────────────────┐    │  │  │    │
│  │  │  │         │         │ MariaDB Pod (Moodle DB only)    │    │  │  │    │
│  │  │  │         │         │ backed up daily to GCS bucket   │    │  │  │    │
│  │  │  │         │         └─────────────────────────────────┘    │  │  │    │
│  │  │  │         │                                                │  │  │    │
│  │  │  │         └──→ connects to Cloud SQL (db-subnet below)     │  │  │    │
│  │  │  │                                                          │  │  │    │
│  │  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │  │  │    │
│  │  │  │  │ ArgoCD      │  │ Prometheus  │  │ Grafana         │   │  │  │    │
│  │  │  │  │ (GitOps)    │  │ (Metrics)   │  │ (Dashboards)    │   │  │  │    │
│  │  │  │  └─────────────┘  └─────────────┘  └─────────────────┘   │  │  │    │
│  │  │  └──────────────────────────────────────────────────────────┘  │  │    │
│  │  │                                                                │  │    │
│  │  │  ┌─── GKE Node 2-3 (autoscaled when needed) ───────────────┐   │  │    │
│  │  │  │  Provisioned by Cluster Autoscaler when pods can't fit  │   │  │    │
│  │  │  │  on Node 1. Max 3 nodes. Removed when no longer needed. │   │  │    │
│  │  │  └─────────────────────────────────────────────────────────┘   │  │    │
│  │  └────────────────────────────────────────────────────────────────┘  │    │
│  │         │                                                            │    │
│  │         │ Private Service Access (VPC Peering)                       │    │
│  │         ▼                                                            │    │
│  │  ┌─── db-subnet (10.0.2.0/24) ── PRIVATE ────────────────────────┐   │    │
│  │  │                                                               │   │    │
│  │  │  ┌───────────────────────────────────────────────────────┐    │   │    │
│  │  │  │ Cloud SQL (PostgreSQL 15)                             │    │   │    │
│  │  │  │ Instance: esmos-healthcare-postgres                   │    │   │    │
│  │  │  │ Tier: db-f1-micro  │  Private IP only  │  Backups: On │    │   │    │
│  │  │  │ Database: odoo     │  User: odooadmin                 │    │   │    │
│  │  │  └───────────────────────────────────────────────────────┘    │   │    │
│  │  └───────────────────────────────────────────────────────────────┘   │    │
│  │                                                                      │    │
│  │  ┌─── Firewall Rules ────────────────────────────────────────────┐   │    │
│  │  │  DENY   all inbound from 0.0.0.0/0 to tag:gke-node (pri 1000) │   │    │
│  │  │  ALLOW  all internal traffic from 10.0.0.0/8         (pri 900)│   │    │
│  │  └───────────────────────────────────────────────────────────────┘   │    │
│  │                                                                      │    │
│  │  ┌─── Access (No public endpoint) ────────────────────────────────┐  │    │
│  │  │  All services use ClusterIP (internal only)                    │  │    │
│  │  │  Access method: kubectl port-forward from authorized machine   │  │    │
│  │  │  Moodle IP whitelist: 116.87.48.126/32 (ingress annotation)    │  │    │
│  │  └────────────────────────────────────────────────────────────────┘  │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

┌─── External Services (outside GCP) ───────────────────────────────────────────┐
│                                                                               │
│  GitHub Repository                  GitHub Actions                            │
│  ├── /terraform/*                   ├── PR → terraform plan (RFC)             │
│  ├── /kubernetes/*                  ├── Merge → terraform apply (Deploy)      │
│  └── ArgoCD syncs from here         └── Manual → terraform destroy (Teardown) │
│                                                                               │
│  Workload Identity Federation (OIDC)                                          │
│  └── GitHub Actions authenticates to GCP without stored credentials           │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Scaling Behavior (HPA + Cluster Autoscaler)

```
                    Normal                          Training Day (50 users)
                    ──────                          ───────────────────────

Node 1              Node 1                          Node 1              Node 2          Node 3
┌────────────┐      ┌────────────┐                  ┌────────────┐      ┌────────────┐  ┌────────────┐
│ Odoo    x1 │      │ Odoo    x1 │     HPA          │ Odoo    x1 │      │ Moodle  x1 │  │ Moodle  x1 │
│ Moodle  x1 │  ──→ │ Moodle  x1 │  ──scales──→     │ Moodle  x1 │      │ MariaDB    │  │            │
│ ArgoCD     │      │ ArgoCD     │   to 3 pods      │ ArgoCD     │      │            │  │            │
│ Monitoring │      │ Monitoring │                  │ Monitoring │      │            │  │            │
└────────────┘      └────────────┘                  └────────────┘      └────────────┘  └────────────┘
  CPU: 30%            CPU: 70%+                        CPU: 50%            CPU: 40%       CPU: 30%

                    HPA triggers at 70% CPU.
                    Cluster Autoscaler adds Node 2-3 when pods can't fit.
                    After load drops, scales back to 1 pod + 1 node (max 3 nodes).
```

## Project Structure

```
├── .github/workflows/deploy.yml          # CI/CD pipeline (plan/apply/destroy)
├── scripts/
│   ├── bootstrap.sh                      # One-time GCP setup
│   └── teardown.sh                       # Destroy all resources
├── terraform/
│   ├── provider.tf                       # GCP, Helm, Kubernetes providers
│   ├── vpc.tf                            # VPC, subnets, firewall rules, private service access
│   ├── gke.tf                            # GKE cluster + node pool
│   ├── db.tf                             # Cloud SQL for PostgreSQL
│   └── helm.tf                           # ArgoCD, Prometheus/Grafana, App CRDs
└── kubernetes/
    ├── odoo/
    │   ├── deployment.yaml              # Odoo Deployment, Service, PVCs (official image)
    │   └── argocd-odoo-app.yaml         # ArgoCD Application CRD for Odoo
    └── moodle/
        ├── deployment.yaml              # Moodle + MariaDB Deployments, Services, HPA, PVCs
        ├── argocd-moodle-app.yaml       # ArgoCD Application CRD for Moodle
        ├── backup-cronjob.yaml          # Daily MariaDB backup to GCS
        └── restore.sh                   # Restore from backup
```

## Service Design

### Systems and Users

| System | Purpose | Users | Access |
|--------|---------|-------|--------|
| **Odoo** | Meal plan inventory & operations | Operations staff (post-training) | Internal, authenticated |
| **Helpdesk** (Odoo app or alternative) | Centralized support across Odoo & Moodle | Support managers, all staff | Internal, role-based |
| **Moodle** | Mandatory compliance training (500+ staff) | All healthcare staff | Internal only, IP-whitelisted |
| **Grafana** | Live monitoring dashboard | SRE / operations team | Internal, port-forwarded |

### Service Integration Workflow

```
1. New staff requests access          → Helpdesk ticket created in Odoo
2. Support manager assigns training   → Links staff to Moodle compliance course
3. Staff completes course in Moodle   → Submits completion proof to Helpdesk ticket
4. Support manager verifies           → Creates Odoo account, notifies staff
5. Ticket closed                      → Full audit trail in Helpdesk
```

### Infrastructure Design Decisions

| Decision | Choice | Justification |
|----------|--------|---------------|
| **Cloud provider** | GCP | Full Owner permissions, Workload Identity Federation for CI/CD, free tier GKE zonal cluster |
| **Region** | `asia-southeast1` (Singapore) | Data residency compliance for healthcare client |
| **Cluster** | GKE, 1-3 nodes, e2-medium | Cost-effective (free zonal cluster management), autoscales only when load demands it |
| **Database** | Cloud SQL db-f1-micro | Cheapest tier with automated daily backups and private networking |
| **Moodle DB** | Bundled MariaDB + daily CronJob backup to GCS | Avoids cost of a second Cloud SQL instance; RPO ~24h |
| **Replicas** | 1 per service, HPA scales Moodle to 3 under load | Balances cost and availability — idle replicas waste credits |
| **GitOps** | ArgoCD | Auto-syncs app config from Git, provides rollback UI and audit trail |
| **Monitoring** | Prometheus + Grafana | Live uptime dashboard, resource metrics, alerting capability |
| **CI/CD auth** | Workload Identity Federation | No stored credentials — OIDC-based, rotates automatically |

### Availability and Recovery

| Metric | Target | How |
|--------|--------|-----|
| **Uptime SLA** | 99.5% | Kubernetes self-healing (auto-restart on crash, ~30s recovery) |
| **RTO** (Recovery Time Objective) | < 5 min | Pod restart: ~30s. Node failure: ~2-3 min (autoscaler provisions new node) |
| **RPO** (Recovery Point Objective) | 24 hours | Cloud SQL daily backup (Odoo). MariaDB CronJob daily backup to GCS (Moodle) |
| **Scaling** | 50 concurrent Moodle users | HPA: 1→3 pods at 70% CPU. GKE: 1→3 nodes. |

### Cost Optimization

| Resource | Spec | Est. Monthly Cost |
|----------|------|-------------------|
| GKE cluster (zonal) | Free management fee | $0 |
| 1x e2-medium node | 2 vCPU, 4GB | ~$25 |
| 2nd-3rd node (autoscaled, part-time) | 2 vCPU, 4GB each | ~$5-25 |
| Cloud SQL db-f1-micro | Shared vCPU, 614MB | ~$8 |
| Storage (PVs + backups) | ~30GB total | ~$3 |
| **Total (est.)** | | **~$40-60/month** |

> Shutdown policy: Scale node pool to 0 or delete cluster when not in use. Redeploy via GitHub Actions in minutes.

## Prerequisites

- [Google Cloud SDK (gcloud)](https://cloud.google.com/sdk/docs/install) installed (`winget install Google.CloudSDK` on Windows)
- A GCP account with billing enabled
- A GitHub account

## Deployment (End-to-End)

### Step 1: Login to GCP

```bash
gcloud auth login
```

Your browser will open — sign in with your Google account.

### Step 2: Run the bootstrap script

```bash
bash scripts/bootstrap.sh
```

This creates the GCP project, enables APIs, sets up the Terraform state bucket, and configures a Service Account with Workload Identity for GitHub Actions. At the end, it prints 4 secrets.

### Step 3: Add secrets to GitHub

Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **Repository secrets** and add:

| Secret Name                        | Description                              |
|------------------------------------|------------------------------------------|
| `GCP_PROJECT_ID`                   | GCP Project ID                           |
| `GCP_WORKLOAD_IDENTITY_PROVIDER`   | Workload Identity Provider resource name |
| `GCP_SERVICE_ACCOUNT`              | Service Account email                    |
| `DB_ADMIN_PASSWORD`                | PostgreSQL admin password                |

### Step 4: Push and deploy

```bash
git add .
git commit -m "Initial deployment"
git push origin main
```

To follow the RFC workflow:
1. Create a feature branch and push
2. Open a Pull Request — GitHub Actions runs `terraform plan` (RFC review)
3. Review the plan, then merge — GitHub Actions runs `terraform apply`

### Step 5: Verify and configure

After the pipeline completes:

```bash
# Get cluster credentials
gcloud container clusters get-credentials esmos-healthcare-gke --zone asia-southeast1-a

# Check all pods and ArgoCD apps
kubectl get pods -A
kubectl get applications -n argocd

# Get Cloud SQL private IP and update Odoo config
gcloud sql instances describe esmos-healthcare-postgres --format="value(ipAddresses[0].ipAddress)"
# Copy the IP, then update kubernetes/odoo/deployment.yaml → HOST env var with this IP
# Push the change — ArgoCD will auto-sync Odoo with the correct DB connection
```

### Step 6: Access services

```bash
# ArgoCD dashboard (each command needs its own terminal)
kubectl port-forward svc/argocd-server -n argocd 8443:443
# → https://localhost:8443

# Grafana monitoring dashboard
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# → http://localhost:3000 (admin / esmos-admin)

# Odoo
kubectl port-forward svc/odoo -n odoo 8069:8069
# → http://localhost:8069

# Moodle
kubectl port-forward svc/moodle -n moodle 8080:8080
# → http://localhost:8080
```

### Step 7: Enable Moodle backup CronJob

```bash
kubectl apply -f kubernetes/moodle/backup-cronjob.yaml
```

This creates a daily backup job that dumps MariaDB to the GCS bucket at 2am SGT.

### Step 8: Set up Odoo Helpdesk

> Note: Odoo Community Edition does not include the Enterprise Helpdesk module.
> Use the built-in **Helpdesk** alternative or install a free helpdesk/ticketing app from the Odoo App Store.

1. Login to Odoo → **Apps** menu
2. Search for a helpdesk/ticketing app → click **Install**
3. Configure helpdesk teams and SLA policies

## Backups and Recovery

### Automated Backups

| System | Method | Schedule | Retention | Location |
|--------|--------|----------|-----------|----------|
| Odoo (Cloud SQL) | GCP automated backup | Daily | 7 days | GCP-managed |
| Moodle (MariaDB) | CronJob `mysqldump` | Daily at 2am SGT | 7 days | `gs://esmos-healthcare-tfstate/moodle-backups/` |

### Restore Moodle from Backup

```bash
# List available backups
bash kubernetes/moodle/restore.sh

# Restore a specific backup
bash kubernetes/moodle/restore.sh moodle-backup-20260314-020000.sql
```

### Restore Odoo (Cloud SQL)

```bash
# List available backups
gcloud sql backups list --instance=esmos-healthcare-postgres

# Restore from a backup
gcloud sql backups restore <BACKUP_ID> --restore-instance=esmos-healthcare-postgres
```

## Teardown

To destroy all GCP resources:

```bash
bash scripts/teardown.sh
```

Type `destroy` when prompted. This removes the GKE cluster, database, networking, state bucket, and the Service Account.

You can also teardown from GitHub without the CLI:
1. Go to **Actions** → **Terraform Deploy Pipeline** → **Run workflow**
2. Select **destroy** from the dropdown → click **Run workflow**

## Redeployment (After Teardown)

**Option A — From GitHub (no CLI needed):**
1. Go to **Actions** → **Terraform Deploy Pipeline** → **Run workflow**
2. Select **apply** from the dropdown → click **Run workflow**

**Option B — Via Git push:**
1. Make any change to a file in `terraform/` (even a comment) — the pipeline only triggers on `terraform/**` changes
2. Push to main or open a PR and merge

> Note: If you used `scripts/teardown.sh` (which also deletes the state bucket and Service Account), you need to run `bash scripts/bootstrap.sh` again first and re-add the GitHub secrets.

## Security and Compliance

| Control | Implementation |
|---------|----------------|
| **Data residency** | All resources in `asia-southeast1` (Singapore) |
| **Network isolation** | GKE private nodes, firewall deny-all internet inbound |
| **Database security** | Cloud SQL private IP only, no public access |
| **Access control** | No public endpoints; access via `kubectl port-forward`. Moodle IP-whitelisted (116.87.48.126/32). Odoo access requires training completion |
| **Least privilege** | All containers run as non-root (UID 1001), pod security contexts enforced |
| **CI/CD auth** | Workload Identity Federation — no stored credentials, OIDC-based |
| **Backups** | Cloud SQL daily (Odoo), CronJob daily to GCS (Moodle), 7-day retention |
| **Monitoring** | Prometheus metrics + Grafana dashboards for uptime and resource usage |
| **Audit trail** | ArgoCD sync history, Git commit history, Helpdesk ticket trail |
| **Change management** | PR-based RFC workflow: plan on PR, apply on merge |

## Change Management (RFC Workflow)

Every infrastructure change follows the Request for Change process:

```
1. Create feature branch     → Developer proposes change
2. Open Pull Request          → GitHub Actions runs terraform plan
3. Team reviews plan          → Risk assessment, impact analysis
4. Merge to main              → GitHub Actions runs terraform apply
5. ArgoCD auto-syncs          → Application changes deployed
6. Grafana verifies           → Monitor for anomalies post-change
```

Rollback: Revert the git commit → ArgoCD auto-syncs to previous state.

## Configuration

| Setting | File | Default |
|---------|------|---------|
| GCP region | `terraform/provider.tf` | `asia-southeast1` (Singapore) |
| Node size | `terraform/gke.tf` | `e2-medium` (2 vCPU, 4GB) |
| Node count | `terraform/gke.tf` | 1-3 (autoscaling) |
| Moodle replicas | `kubernetes/moodle/deployment.yaml` | 1 (HPA scales to 3) |
| Grafana password | `terraform/helm.tf` | `esmos-admin` |
| Backup schedule | `kubernetes/moodle/backup-cronjob.yaml` | Daily at 2am |
