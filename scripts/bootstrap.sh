#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────
# ESMOS Healthcare DevSecOps - One-Time Bootstrap Script
# ─────────────────────────────────────────────────────────
# Sets up:
#   1. GCP project + APIs
#   2. Terraform state bucket (GCS)
#   3. Service Account for GitHub Actions (Workload Identity)
#   4. Generates DB password
# ─────────────────────────────────────────────────────────

echo "============================================"
echo "  ESMOS Healthcare - Bootstrap Setup (GCP)"
echo "============================================"
echo ""

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
  echo "  Install it: winget install Google.CloudSDK"
  exit 1
fi

# ── Step 1: Login + Project ──
echo "[1/5] Checking GCP login..."
ACCOUNT=$(gcloud config get-value account 2>/dev/null)
if [ -z "$ACCOUNT" ] || [ "$ACCOUNT" = "(unset)" ]; then
  echo "  Not logged in. Opening browser..."
  gcloud auth login
fi

echo ""
echo "  Available projects:"
gcloud projects list --format="table(projectId, name)"
echo ""
read -p "  Enter your GCP Project ID (or 'new' to create one): " PROJECT_ID

if [ "$PROJECT_ID" = "new" ]; then
  read -p "  Enter a new Project ID (lowercase, dashes ok): " PROJECT_ID
  gcloud projects create "$PROJECT_ID" --name="ESMOS Healthcare"
  echo "  Project created: $PROJECT_ID"

  # Link billing account
  echo ""
  echo "  Available billing accounts:"
  gcloud billing accounts list --format="table(name, displayName, open)"
  echo ""
  read -p "  Enter Billing Account ID: " BILLING_ID
  gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ID"
fi

gcloud config set project "$PROJECT_ID"
echo "  Using project: $PROJECT_ID"
echo ""

# ── Step 2: Enable APIs ──
echo "[2/5] Enabling required GCP APIs..."
APIS=(
  "container.googleapis.com"
  "sqladmin.googleapis.com"
  "compute.googleapis.com"
  "servicenetworking.googleapis.com"
  "iam.googleapis.com"
  "iamcredentials.googleapis.com"
  "cloudresourcemanager.googleapis.com"
  "sts.googleapis.com"
)
for api in "${APIS[@]}"; do
  echo "  Enabling $api..."
  gcloud services enable "$api" --quiet
done
echo "  All APIs enabled."
echo ""

# ── Step 3: Create Terraform state bucket ──
echo "[3/5] Creating Terraform state bucket..."
BUCKET="esmos-healthcare-tfstate"
REGION="asia-southeast1"

if ! gcloud storage buckets describe "gs://$BUCKET" &>/dev/null; then
  gcloud storage buckets create "gs://$BUCKET" \
    --location="$REGION" \
    --uniform-bucket-level-access
  echo "  Bucket created: gs://$BUCKET"
else
  echo "  Bucket already exists: gs://$BUCKET"
fi

# Enable versioning for state safety
gcloud storage buckets update "gs://$BUCKET" --versioning
echo ""

# ── Step 4: Create Service Account + Workload Identity for GitHub Actions ──
echo "[4/5] Creating Service Account for GitHub Actions..."

SA_NAME="github-actions"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Create service account
gcloud iam service-accounts create "$SA_NAME" \
  --display-name="GitHub Actions CI/CD" \
  --quiet 2>/dev/null || echo "  (Service account already exists)"

# Wait for propagation
echo "  Waiting for service account to propagate..."
sleep 10

# Grant roles
for role in "roles/container.admin" "roles/compute.admin" "roles/cloudsql.admin" \
            "roles/iam.serviceAccountUser" "roles/storage.admin" "roles/servicenetworking.networksAdmin"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="$role" \
    --quiet --no-user-output-enabled
done
echo "  Service account created: $SA_EMAIL"

# Setup Workload Identity Federation for GitHub Actions
echo ""
read -p "  Enter your GitHub repo (e.g. JarudeC/esmos-healthcare-devsecops-platform): " GITHUB_REPO

POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"

# Create workload identity pool
gcloud iam workload-identity-pools create "$POOL_NAME" \
  --location="global" \
  --display-name="GitHub Actions Pool" \
  --quiet 2>/dev/null || echo "  (Pool already exists)"

# Create provider
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
  --location="global" \
  --workload-identity-pool="$POOL_NAME" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --quiet 2>/dev/null || echo "  (Provider already exists)"

# Get the pool ID
POOL_ID=$(gcloud iam workload-identity-pools describe "$POOL_NAME" \
  --location="global" --format="value(name)")

# Allow GitHub repo to impersonate the service account
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${GITHUB_REPO}" \
  --quiet --no-user-output-enabled

PROVIDER_FULL="${POOL_ID}/providers/${PROVIDER_NAME}"
echo "  Workload Identity configured for: $GITHUB_REPO"
echo ""

# ── Step 5: Generate DB password ──
echo "[5/5] Generating credentials..."
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 20)

echo ""
echo "============================================"
echo "  SETUP COMPLETE - Add these to GitHub"
echo "============================================"
echo ""
echo "Go to: https://github.com/${GITHUB_REPO}/settings/secrets/actions"
echo ""
echo "Add these 4 repository secrets:"
echo ""
echo "  Name: GCP_PROJECT_ID"
echo "  Value: $PROJECT_ID"
echo ""
echo "  Name: GCP_WORKLOAD_IDENTITY_PROVIDER"
echo "  Value: $PROVIDER_FULL"
echo ""
echo "  Name: GCP_SERVICE_ACCOUNT"
echo "  Value: $SA_EMAIL"
echo ""
echo "  Name: DB_ADMIN_PASSWORD"
echo "  Value: $DB_PASSWORD"
echo ""
echo "============================================"
echo "  NEXT STEPS"
echo "============================================"
echo "  1. Add the 4 secrets above to GitHub"
echo "  2. git add . && git commit -m 'Initial setup' && git push"
echo "  3. Create a PR to trigger terraform plan"
echo "  4. Merge PR to deploy everything"
echo "============================================"
