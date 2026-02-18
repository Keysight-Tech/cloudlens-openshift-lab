#!/bin/bash
# ============================================================================
# DESTROY - CloudLens OpenShift Visibility Lab
# ============================================================================
# Completely removes all lab resources:
#   1. CyPerf K8s resources (if deployed)
#   2. OpenShift workloads (nginx-demo)
#   3. ROSA cluster (via terraform destroy)
#   4. All EC2 instances, VPC, and AWS resources
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$BASE_DIR/terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "============================================================================"
echo "  CloudLens OpenShift Lab - Destroy"
echo "============================================================================"
echo ""
echo -e "${RED}WARNING: This will permanently delete ALL lab resources including the ROSA cluster.${NC}"
echo ""
read -p "Type 'destroy' to confirm: " CONFIRM
if [[ "$CONFIRM" != "destroy" ]]; then
    echo "Aborted."
    exit 1
fi

# ============================================================================
# STEP 1: Clean up OpenShift workloads
# ============================================================================

if oc whoami &>/dev/null 2>&1; then
    log_info "Cleaning up OpenShift workloads..."

    oc delete pod,svc,deployment,configmap,serviceaccount,route --all -n cyperf --ignore-not-found 2>/dev/null || true
    oc delete deployment,svc,configmap,route -l app=nginx-demo -n default --ignore-not-found 2>/dev/null || true

    log_success "OpenShift workloads removed"
else
    log_warning "Not logged in to OpenShift. Skipping workload cleanup."
    log_warning "Cluster will be destroyed by terraform anyway."
fi

# ============================================================================
# STEP 2: Terraform destroy (ROSA + all EC2 + VPC)
# ============================================================================

log_info "Running terraform destroy..."
cd "$TF_DIR"

terraform destroy -auto-approve

log_success "All infrastructure destroyed"

# ============================================================================
# STEP 3: Clean up ROSA account roles (optional - reusable across clusters)
# ============================================================================

DEPLOYMENT_PREFIX=$(terraform output -raw deployment_prefix 2>/dev/null || echo "cloudlens-lab")

echo ""
log_warning "ROSA account roles (${DEPLOYMENT_PREFIX}-HCP-ROSA-*) are NOT deleted by default."
log_warning "They are reusable across multiple clusters in the same account."
read -p "Delete ROSA account roles? [y/N]: " DELETE_ROLES
if [[ "${DELETE_ROLES,,}" == "y" ]]; then
    log_info "Deleting ROSA account roles..."
    rosa delete account-roles --prefix "$DEPLOYMENT_PREFIX" --mode auto --yes 2>/dev/null || true
    log_success "Account roles deleted"
fi

echo ""
echo "============================================================================"
echo "  Destroy Complete"
echo "============================================================================"
echo ""
