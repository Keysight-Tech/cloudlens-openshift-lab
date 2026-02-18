#!/bin/bash
# ============================================================================
# STOP ALL - Stop EC2 instances and scale down ROSA machine pool
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
echo "  Stopping CloudLens OpenShift Lab (cost saving)"
echo "============================================================================"
echo ""

AWS_PROFILE=$(cd "$TF_DIR" && terraform output -raw aws_profile 2>/dev/null || echo "cloudlens-lab")
AWS_REGION=$(cd "$TF_DIR" && terraform output -raw aws_region 2>/dev/null || echo "us-west-2")
CLUSTER_NAME=$(cd "$TF_DIR" && terraform output -raw rosa_cluster_name 2>/dev/null || echo "")

# Scale down ROSA machine pool first (nodes need to drain)
if [[ -n "$CLUSTER_NAME" ]]; then
    log_info "Scaling down ROSA machine pool to 0..."
    rosa edit machinepool worker \
        --cluster "$CLUSTER_NAME" \
        --min-replicas 0 \
        --max-replicas 4 \
        --replicas 0 2>/dev/null || true
    log_success "ROSA machine pool scale-down initiated (nodes will drain)"
    log_warning "Note: ROSA HCP control plane continues running (billed by Red Hat)"
else
    log_warning "Could not determine ROSA cluster name. Scale down manually."
fi

# Stop EC2 instances
log_info "Stopping EC2 instances..."
INSTANCE_IDS=$(cd "$TF_DIR" && terraform output -json all_instance_ids 2>/dev/null | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin)))" 2>/dev/null || echo "")

if [[ -n "$INSTANCE_IDS" ]]; then
    aws ec2 stop-instances --instance-ids $INSTANCE_IDS \
        --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null
    log_success "Stop signal sent to all EC2 instances"
else
    log_warning "Could not retrieve instance IDs from terraform output"
fi

echo ""
log_success "Lab stopped."
log_warning "Note: NAT Gateways and Elastic IPs still incur charges when stopped."
log_warning "Run 'terraform destroy' to remove all resources and stop all billing."
echo ""
