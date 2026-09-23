#!/bin/bash

# ===========================================================================================
#
# What does this script do?
# Sets up a Service Account for GitHub Actions, reusing the shared pool/provider
# created by 2-oidc-bootstrap-shared.sh:
#   STEP 1: Verify the shared Workload Identity Pool + Provider exist
#   STEP 2: Create the Service Account (if missing)
#   STEP 3: Grant roles/owner to the Service Account
#   STEP 4: Bind the Service Account to GitHub, scoped per SCOPE (see below)
#   STEP 5: Output values needed for the GitHub Actions workflow(s)
#
# Safe to re-run: existing SA/bindings are detected and left as-is.
#
# SCOPE controls how broadly the resulting GitHub secrets can be used:
#   SCOPE=repo (default) — one SA per app, usable only from GITHUB_REPO.
#                           Run this once per app (5 apps = 5 runs, each with
#                           its own APP_NAME + GITHUB_REPO).
#   SCOPE=org             — ONE shared SA, usable from ANY repo under GITHUB_ORG.
#                           Run this ONCE total; every app repo gets the same
#                           GCP_SERVICE_ACCOUNT / GCP_WORKLOAD_IDENTITY_PROVIDER
#                           secret values. Simpler, but any workflow in any repo
#                           in the org (including future repos, and fork-triggered
#                           PR workflows on public repos) can then act as this SA —
#                           which already holds roles/owner (full project admin).
#                           Only use this if you accept that trade-off.
#
# Required env vars:
#   APP_NAME     — short name, used to derive the SA name (e.g. i27helpdesk-auth,
#                  or just "shared" when SCOPE=org)
#   GITHUB_REPO  — exact GitHub repo name to scope to. Required when SCOPE=repo,
#                  ignored when SCOPE=org.
#
# ===========================================================================================
# Execute this command 
# SCOPE=org APP_NAME=shared ./3-oidc-app-setup.sh
# ===========================================================================================

set -euo pipefail

export SCOPE="${SCOPE:-repo}"

if [ "$SCOPE" != "repo" ] && [ "$SCOPE" != "org" ]; then
  echo "ERROR: SCOPE must be 'repo' or 'org' (got '$SCOPE')." >&2
  exit 1
fi

if [ -z "${APP_NAME:-}" ]; then
  echo "ERROR: APP_NAME must be set." >&2
  echo "Examples:" >&2
  echo "  APP_NAME=i27helpdesk-auth GITHUB_REPO=i27-helpdesk-auth-service ./3-oidc-app-setup.sh" >&2
  echo "  SCOPE=org APP_NAME=shared ./3-oidc-app-setup.sh" >&2
  exit 1
fi

if [ "$SCOPE" = "repo" ] && [ -z "${GITHUB_REPO:-}" ]; then
  echo "ERROR: GITHUB_REPO must be set when SCOPE=repo." >&2
  exit 1
fi

# ── CONFIGURATION ──────────────────────────────────────────────
export PROJECT_ID="${PROJECT_ID:-project-297df0e3-3d6b-40a7-aab}"
export GITHUB_ORG="${GITHUB_ORG:-devopswithcloud}"
export POOL_ID="${POOL_ID:-github-actions-pool}"
export PROVIDER_ID="${PROVIDER_ID:-github-actions-provider}"
export SA_NAME="${APP_NAME}-github-actions-sa"

# ── DERIVED VALUES ──────────────────────────────────────────────
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" \
  --format='value(projectNumber)')
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "============================="
echo "GCP OIDC APP SETUP"
echo "============================="
echo "Project ID     : $PROJECT_ID"
echo "Project Number : $PROJECT_NUMBER"
echo "Scope          : $SCOPE"
echo "GitHub Org     : $GITHUB_ORG"
if [ "$SCOPE" = "repo" ]; then
  echo "GitHub Repo    : $GITHUB_REPO"
fi
echo "Service Account: $SA_EMAIL"
echo "Shared Pool    : $POOL_ID"
echo "Shared Provider: $PROVIDER_ID"
echo "============================="
echo ""

# ── STEP 1: Verify shared pool + provider exist ─────────────────
echo "Step 1: Verifying shared Workload Identity Pool + Provider exist..."
POOL_STATE=$(gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$PROJECT_ID" --location="global" \
  --format='value(state)' 2>/dev/null || true)
if [ "$POOL_STATE" != "ACTIVE" ]; then
  echo "ERROR: Pool '$POOL_ID' not found or not ACTIVE (state: '${POOL_STATE:-missing}') in project '$PROJECT_ID'." >&2
  echo "Run 2-oidc-bootstrap-shared.sh first." >&2
  exit 1
fi
PROVIDER_STATE=$(gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
  --project="$PROJECT_ID" --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --format='value(state)' 2>/dev/null || true)
if [ "$PROVIDER_STATE" != "ACTIVE" ]; then
  echo "ERROR: Provider '$PROVIDER_ID' not found or not ACTIVE (state: '${PROVIDER_STATE:-missing}') in pool '$POOL_ID'." >&2
  echo "Run 2-oidc-bootstrap-shared.sh first." >&2
  exit 1
fi
echo "  Found."
echo ""

# ── STEP 2: Create this app's Service Account ────────────────────
echo "Step 2: Creating Service Account for $APP_NAME..."
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "  Service Account '$SA_EMAIL' already exists — skipping."
else
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="GitHub Actions Service Account ($APP_NAME)"
  echo "  Service Account created: $SA_EMAIL"
fi
echo ""

# ── STEP 3: Grant Permissions ────────────────────────────────────
echo "Step 3: Granting permissions to Service Account..."
# Granting Project Owner for now — replace with least-privilege roles later
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/owner" \
  --condition=None \
  >/dev/null
echo "Permissions granted"
echo ""

# ── STEP 4: Bind Service Account to GitHub ───────────────────────
if [ "$SCOPE" = "org" ]; then
  echo "Step 4: Binding Service Account to ANY repo under org '$GITHUB_ORG'..."
  BINDING_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository_owner/${GITHUB_ORG}"
else
  echo "Step 4: Binding Service Account to $GITHUB_ORG/$GITHUB_REPO only..."
  BINDING_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"
fi
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="$BINDING_MEMBER" \
  >/dev/null
echo "Service Account binding complete."
echo ""

# ── STEP 5: OUTPUT ────────────────────────────────────────────────
echo "============================="
echo "APP SETUP COMPLETE: $APP_NAME"
echo "============================="
echo ""
if [ "$SCOPE" = "org" ]; then
  echo "Add these as GitHub Secrets in EVERY repo under $GITHUB_ORG that needs GCP access:"
  echo "  Repo -> Settings -> Secrets and variables -> Actions -> New secret"
  echo "(Same two values for every repo — this SA is not repo-specific.)"
else
  echo "Add these as GitHub Secrets in $GITHUB_REPO:"
  echo "  Repo -> Settings -> Secrets and variables -> Actions -> New secret"
fi
echo ""
echo "GCP_SERVICE_ACCOUNT:"
echo "  ${SA_EMAIL}"
echo ""
echo "GCP_WORKLOAD_IDENTITY_PROVIDER:"
echo "  $(gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --format='value(name)')"
echo ""
echo "============================="
