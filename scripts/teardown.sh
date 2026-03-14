#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────
# ESMOS Healthcare DevSecOps - Teardown Script (GCP)
# ─────────────────────────────────────────────────────────
# Destroys ALL resources:
#   1. Terraform-managed resources (GKE, Cloud SQL, VPC, etc.)
#   2. Terraform state bucket
#   3. Service Account + Workload Identity
# ─────────────────────────────────────────────────────────

echo "============================================"
echo "  ESMOS Healthcare - TEARDOWN (GCP)"
echo "============================================"
echo ""
echo "  This will DESTROY everything:"
echo "    - GKE cluster"
echo "    - Cloud SQL database"
echo "    - VPC network"
echo "    - Terraform state bucket"
echo "    - Service account"
echo ""
read -p "  Are you sure? Type 'destroy' to confirm: " CONFIRM
echo ""

if [ "$CONFIRM" != "destroy" ]; then
  echo "Aborted."
  exit 1
fi

# ── Check gcloud (add to PATH on Windows/Git Bash if needed) ──
if ! command -v gcloud &> /dev/null; then
  for dir in \
    "$LOCALAPPDATA/Google/Cloud SDK/google-cloud-sdk/bin" \
    "/c/Users/$USER/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin" \
    "/c/Program Files/Google/Cloud SDK/google-cloud-sdk/bin" \
    "/c/Program Files (x86)/Google/Cloud SDK/google-cloud-sdk/bin"; do
    if [ -f "$dir/gcloud.cmd" ]; then
      export PATH="$PATH:$dir"
      break
    fi
  done
fi

if ! command -v gcloud &> /dev/null; then
  echo "ERROR: gcloud CLI not found."
  exit 1
fi

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  echo "ERROR: No GCP project set. Run: gcloud config set project <PROJECT_ID>"
  exit 1
fi
echo "  Project: $PROJECT_ID"
echo ""

# ── Step 1: Terraform Destroy ──
echo "[1/4] Running terraform destroy..."
cd "$(dirname "$0")/../terraform"

export TF_VAR_project_id="$PROJECT_ID"
export TF_VAR_db_admin_password="placeholder"

terraform init -input=false
terraform destroy -auto-approve
echo ""

# ── Step 2: Delete Terraform state bucket ──
echo "[2/4] Deleting Terraform state bucket..."
BUCKET="esmos-healthcare-tfstate"
gcloud storage rm --recursive "gs://$BUCKET" --quiet 2>/dev/null || true
echo "  Bucket deleted."
echo ""

# ── Step 3: Delete Service Account ──
echo "[3/4] Cleaning up Service Account..."
SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud iam service-accounts delete "$SA_EMAIL" --quiet 2>/dev/null || true
echo "  Service account deleted."
echo ""

# ── Step 4: Delete Workload Identity Pool ──
echo "[4/4] Cleaning up Workload Identity..."
gcloud iam workload-identity-pools delete "github-pool" \
  --location="global" --quiet 2>/dev/null || true
echo "  Workload Identity pool deleted."
echo ""

echo "============================================"
echo "  TEARDOWN COMPLETE"
echo "============================================"
echo "  All GCP resources have been destroyed."
echo "  You can also remove the GitHub secrets manually:"
echo "    - GCP_PROJECT_ID"
echo "    - GCP_WORKLOAD_IDENTITY_PROVIDER"
echo "    - GCP_SERVICE_ACCOUNT"
echo "    - DB_ADMIN_PASSWORD"
echo "============================================"
