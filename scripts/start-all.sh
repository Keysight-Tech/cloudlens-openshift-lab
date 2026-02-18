#!/bin/bash
# ============================================================================
# START ALL - Start EC2 instances and scale up ROSA machine pool
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")/terraform"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo ""
echo "============================================================================"
echo "  Starting CloudLens OpenShift Lab"
echo "============================================================================"
echo ""

AWS_PROFILE=$(cd "$TF_DIR" && terraform output -raw aws_profile 2>/dev/null || echo "cloudlens-lab")
AWS_REGION=$(cd "$TF_DIR" && terraform output -raw aws_region 2>/dev/null || echo "us-west-2")
CLUSTER_NAME=$(cd "$TF_DIR" && terraform output -raw rosa_cluster_name 2>/dev/null || echo "")

# Start EC2 instances
log_info "Starting EC2 instances..."
INSTANCE_IDS=$(cd "$TF_DIR" && terraform output -json all_instance_ids 2>/dev/null | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin)))" 2>/dev/null || echo "")

if [[ -n "$INSTANCE_IDS" ]]; then
    aws ec2 start-instances --instance-ids $INSTANCE_IDS \
        --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null
    log_success "EC2 instances started"
    aws ec2 wait instance-running --instance-ids $INSTANCE_IDS \
        --region "$AWS_REGION" --profile "$AWS_PROFILE"
    log_success "All instances running"
else
    log_warning "Could not retrieve instance IDs from terraform output"
fi

# Scale up ROSA machine pool
if [[ -n "$CLUSTER_NAME" ]]; then
    log_info "Scaling up ROSA machine pool..."
    rosa edit machinepool worker \
        --cluster "$CLUSTER_NAME" \
        --min-replicas 2 \
        --max-replicas 4 \
        --replicas 2 2>/dev/null || true
    log_success "ROSA machine pool scaling initiated"
else
    log_warning "Could not determine ROSA cluster name. Scale manually with:"
    log_warning "  rosa edit machinepool worker --cluster <name> --replicas 2"
fi

echo ""
log_success "Lab started. Wait ~5 min for instances to be fully ready."
echo ""
