#!/bin/bash

# ===========================================================================================
#
# What does this script do?
# Tears down the GCP resources created for one app's GitHub Actions OIDC setup:
#   - SA -> workload identity pool binding
#   - OIDC provider
#   - Workload identity pool
#   - Project-level roles/owner binding on the SA
#   - The service account itself
#
# Safe to run against a partially-created (failed) setup: every step is best-effort
# and won't abort the script if that particular resource never got created.
#
# Defaults below match the original i27-helpdesk-auth-service/oidc.sh run, so this
# can be run immediately to clean up that broken state. Override via env vars for
# any other app/pool you need to tear down.
#
# ===========================================================================================
# Execute this script by the below command
# SA_NAME=shared-github-actions-sa POOL_ID=github-actions-pool bash 1-oidc-cleanup.sh
# ===========================================================================================

set -u

# ── CONFIGURATION — override via env vars if needed ───────────
export PROJECT_ID="${PROJECT_ID:-project-297df0e3-3d6b-40a7-aab}"
export GITHUB_ORG="${GITHUB_ORG:-devopswithcloud}"
export GITHUB_REPO="${GITHUB_REPO:-i27-helpdesk-auth-service}"
export SA_NAME="${SA_NAME:-i27helpdesk-github-actions-sa}"
export POOL_ID="${POOL_ID:-i27helpdesk-auth-actions-pool}"
export PROVIDER_ID="${PROVIDER_ID:-github-actions-provider}"

# ── DERIVED VALUES ─────────────────────────────────────────────
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" \
  --format='value(projectNumber)' 2>/dev/null)
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "============================="
echo "GCP OIDC CLEANUP"
echo "============================="
echo "Project ID     : $PROJECT_ID"
echo "Project Number : $PROJECT_NUMBER"
echo "Service Account: $SA_EMAIL"
echo "Pool ID        : $POOL_ID"
echo "Provider ID    : $PROVIDER_ID"
echo "============================="
echo ""

# ── STEP 1: Remove workloadIdentityUser binding on the SA ─────
echo "Step 1: Removing workload identity binding on the service account..."
if [ -n "$PROJECT_NUMBER" ]; then
  gcloud iam service-accounts remove-iam-policy-binding "$SA_EMAIL" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}" \
    2>/dev/null || echo "  (skipped — binding or service account not found)"
else
  echo "  (skipped — could not resolve project, likely already gone)"
fi
echo ""

# ── STEP 2: Delete the OIDC provider ───────────────────────────
echo "Step 2: Deleting OIDC provider..."
gcloud iam workload-identity-pools providers delete "$PROVIDER_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --quiet \
  2>/dev/null || echo "  (skipped — provider not found)"
echo ""

# ── STEP 3: Delete the workload identity pool ──────────────────
echo "Step 3: Deleting workload identity pool..."
gcloud iam workload-identity-pools delete "$POOL_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --quiet \
  2>/dev/null || echo "  (skipped — pool not found)"
echo "  Note: GCP soft-deletes pools for ~30 days; the same POOL_ID cannot be"
echo "  recreated until the soft-deleted one is purged or restored."
echo ""

# ── STEP 4: Remove project-level roles/owner binding ───────────
echo "Step 4: Removing project IAM binding (roles/owner) from service account..."
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/owner" \
  2>/dev/null || echo "  (skipped — binding not found)"
echo ""

# ── STEP 5: Delete the service account ─────────────────────────
echo "Step 5: Deleting service account..."
gcloud iam service-accounts delete "$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --quiet \
  2>/dev/null || echo "  (skipped — service account not found)"
echo ""

echo "============================="
echo "CLEANUP COMPLETE"
echo "============================="
echo "Verify with:"
echo "  gcloud iam service-accounts list --project=$PROJECT_ID"
echo "  gcloud iam workload-identity-pools list --project=$PROJECT_ID --location=global"
echo "============================="
