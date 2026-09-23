#!/bin/bash

# ===========================================================================================
#
# What does this script do?
# One-time, per-GCP-project bootstrap for GitHub Actions OIDC:
#   STEP 1: Enable required GCP APIs
#   STEP 2: Create the shared Workload Identity Pool (if missing)
#   STEP 3: Create the shared OIDC Provider linked to GitHub Actions (if missing)
#
# Run this ONCE per GCP project, not once per app. Every app repo then only needs
# 3-oidc-app-setup.sh, which creates its own service account and binds it to this
# same shared pool/provider, scoped to that app's repo only.
#
# Safe to re-run: existing pool/provider are detected and left untouched.
#
# ===========================================================================================

set -euo pipefail

# ── CONFIGURATION — update these values before running ───────
export PROJECT_ID="${PROJECT_ID:-project-297df0e3-3d6b-40a7-aab}"
export GITHUB_ORG="${GITHUB_ORG:-devopswithcloud}"
export POOL_ID="${POOL_ID:-github-actions-pool}"
export PROVIDER_ID="${PROVIDER_ID:-github-actions-provider}"

echo "============================="
echo "GCP OIDC SHARED BOOTSTRAP"
echo "============================="
echo "Project ID  : $PROJECT_ID"
echo "GitHub Org  : $GITHUB_ORG"
echo "Pool ID     : $POOL_ID"
echo "Provider ID : $PROVIDER_ID"
echo "============================="
echo ""

# ── STEP 1: Enable required GCP APIs ─────────────────────────
echo "Step 1: Enabling required GCP APIs..."
gcloud services enable \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="$PROJECT_ID"
echo "APIs enabled"
echo ""

# ── STEP 2: Create the shared Workload Identity Pool ─────────
echo "Step 2: Creating shared Workload Identity Pool (if it doesn't exist)..."
POOL_STATE=$(gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$PROJECT_ID" --location="global" \
  --format='value(state)' 2>/dev/null || true)

if [ "$POOL_STATE" = "ACTIVE" ]; then
  echo "  Pool '$POOL_ID' already exists and is active — skipping."
elif [ "$POOL_STATE" = "DELETED" ]; then
  echo "  Pool '$POOL_ID' exists but is soft-deleted — undeleting..."
  gcloud iam workload-identity-pools undelete "$POOL_ID" \
    --project="$PROJECT_ID" \
    --location="global"
  echo "  Pool undeleted."
else
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --project="$PROJECT_ID" \
    --location="global" \
    --display-name="GitHub Actions Pool (shared)"
  echo "  Pool created."
fi
echo ""

# ── STEP 3: Create the shared OIDC Provider ──────────────────
echo "Step 3: Creating shared OIDC Provider (if it doesn't exist)..."
if gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
  --project="$PROJECT_ID" --location="global" \
  --workload-identity-pool="$POOL_ID" >/dev/null 2>&1; then
  echo "  Provider '$PROVIDER_ID' already exists — skipping."
else
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --project="$PROJECT_ID" \
    --location="global" \
    --workload-identity-pool="$POOL_ID" \
    --display-name="GitHub Actions Provider (shared)" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'"
  echo "  Provider created."
fi
echo ""

echo "============================="
echo "SHARED BOOTSTRAP COMPLETE"
echo "============================="
echo "Provider resource name (needed by 3-oidc-app-setup.sh):"
gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --format='value(name)'
echo ""
echo "Next: for each app, run 3-oidc-app-setup.sh with APP_NAME and GITHUB_REPO set."
echo "============================="
