#!/bin/bash
# ============================================================================
#  CloudLens OpenShift Visibility Lab - Full Deployment Script
# ============================================================================
#  Single script to deploy everything from scratch.
#  Usage: ./scripts/deploy.sh
#
#  What this script does:
#    1. Checks & installs prerequisites (terraform, oc, rosa CLI, aws, jq)
#    2. Validates AWS credentials, Red Hat token & terraform.tfvars
#    3. Runs terraform init + apply (all infrastructure + ROSA cluster)
#    4. Waits for product initialization (CLMS, KVO, ROSA)
#    5. Configures oc for ROSA via oc login
#    6. Deploys OpenShift workloads (nginx-demo + Route)
#    7. Deploys CyPerf agents + test session (if enabled)
#       - Prompts you to activate CyPerf license first
#    8. Generates deployment documentation
#    9. Prints full deployment summary
# ============================================================================

set -euo pipefail

# ============================================================================
# COLORS & HELPERS
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_DIR/terraform"
MANIFESTS_DIR="$REPO_DIR/kubernetes_manifests"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}  STEP $1: $2${NC}"; echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

prompt_continue() {
    echo ""
    read -rp "  Press Enter to continue (or Ctrl+C to abort)... "
    echo ""
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local yn
    if [[ "$default" == "y" ]]; then
        read -rp "  $prompt [Y/n]: " yn
        yn="${yn:-y}"
    else
        read -rp "  $prompt [y/N]: " yn
        yn="${yn:-n}"
    fi
    [[ "$yn" =~ ^[Yy] ]]
}

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then echo "linux"
    else echo "unknown"
    fi
}

OS=$(detect_os)

echo ""
echo -e "${BOLD}${CYAN}============================================================================${NC}"
echo -e "${BOLD}  CloudLens OpenShift Visibility Lab - Full Deployment${NC}"
echo -e "${BOLD}${CYAN}============================================================================${NC}"
echo ""
echo "  This script will deploy the complete lab environment including:"
echo "    - AWS infrastructure (VPC, EC2 instances)"
echo "    - Keysight products (CLMS, KVO, vPB)"
echo "    - ROSA HCP cluster (Red Hat OpenShift Service on AWS)"
echo "    - OpenShift workloads (nginx-demo with Route)"
echo "    - CyPerf traffic generator (if enabled)"
echo "    - Generated deployment documentation"
echo ""
echo -e "  ${YELLOW}Prerequisites you need BEFORE running this script:${NC}"
echo "    1. AWS account with Marketplace subscriptions (CLMS, KVO, vPB)"
echo "    2. EC2 key pair created in your target region"
echo "    3. Red Hat account with ROSA enabled (console.redhat.com)"
echo "    4. OCM API token from console.redhat.com/openshift/token"
echo "    5. Keysight license activation codes (KVO, CloudLens, CyPerf)"
echo ""

prompt_continue

# ============================================================================
# STEP 1: CHECK & INSTALL PREREQUISITES
# ============================================================================
log_step "1/9" "Checking Prerequisites"

MISSING_TOOLS=()

check_tool() {
    local tool="$1"
    local name="$2"
    if command -v "$tool" &>/dev/null; then
        local version
        version=$("$tool" --version 2>&1 | head -1 || echo "installed")
        echo -e "  ${GREEN}✓${NC} $name: $version"
    else
        echo -e "  ${RED}✗${NC} $name: NOT FOUND"
        MISSING_TOOLS+=("$tool")
    fi
}

echo "Checking required tools..."
echo ""
check_tool "terraform" "Terraform"
check_tool "oc"        "OpenShift CLI (oc)"
check_tool "rosa"      "ROSA CLI"
check_tool "aws"       "AWS CLI"
check_tool "jq"        "jq"
check_tool "curl"      "curl"
check_tool "python3"   "Python 3"
echo ""

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    log_warn "Missing tools: ${MISSING_TOOLS[*]}"
    echo ""

    if [[ "$OS" == "macos" ]]; then
        if ! command -v brew &>/dev/null; then
            log_warn "Homebrew not found. Install it from https://brew.sh"
            exit 1
        fi

        if prompt_yes_no "Install missing tools via Homebrew?"; then
            for tool in "${MISSING_TOOLS[@]}"; do
                case "$tool" in
                    terraform) brew install terraform ;;
                    oc)        brew install openshift-cli ;;
                    rosa)
                        echo "  Downloading ROSA CLI..."
                        curl -sL "https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-macosx.tar.gz" | tar xz -C /usr/local/bin
                        chmod +x /usr/local/bin/rosa
                        ;;
                    aws)       brew install awscli ;;
                    jq)        brew install jq ;;
                    curl)      brew install curl ;;
                    python3)   brew install python3 ;;
                esac
            done
            log_success "Tools installed"
        else
            log_error "Please install missing tools and re-run this script."
            exit 1
        fi

    elif [[ "$OS" == "linux" ]]; then
        echo "  Install on Linux:"
        for tool in "${MISSING_TOOLS[@]}"; do
            case "$tool" in
                terraform) echo "    # Terraform: https://developer.hashicorp.com/terraform/install" ;;
                oc)        echo "    curl -sL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz | tar xz -C /usr/local/bin oc kubectl" ;;
                rosa)      echo "    curl -sL https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz | tar xz -C /usr/local/bin" ;;
                aws)       echo "    curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' && unzip awscliv2.zip && sudo ./aws/install" ;;
                jq)        echo "    sudo apt-get install -y jq" ;;
                python3)   echo "    sudo apt-get install -y python3" ;;
            esac
        done
        echo ""
        log_error "Please install the missing tools above and re-run this script."
        exit 1
    else
        log_error "Unsupported OS. Install tools manually and re-run."
        exit 1
    fi
fi

log_success "All prerequisites met"

# ============================================================================
# STEP 2: VALIDATE CONFIGURATION
# ============================================================================
log_step "2/9" "Validating Configuration"

if [[ ! -f "$TF_DIR/terraform.tfvars" ]]; then
    log_warn "terraform.tfvars not found. Creating from template..."
    echo ""
    echo "  You need to configure your deployment settings."
    echo ""

    read -rp "  AWS CLI profile name [cloudlens-lab]: " AWS_PROFILE
    AWS_PROFILE="${AWS_PROFILE:-cloudlens-lab}"

    read -rp "  AWS region [us-west-2]: " AWS_REGION
    AWS_REGION="${AWS_REGION:-us-west-2}"

    read -rp "  EC2 key pair name [cloudlens-lab]: " KEY_PAIR
    KEY_PAIR="${KEY_PAIR:-cloudlens-lab}"

    read -rp "  SSH private key path [~/.ssh/${KEY_PAIR}.pem]: " KEY_PATH
    KEY_PATH="${KEY_PATH:-~/.ssh/${KEY_PAIR}.pem}"

    read -rp "  Deployment prefix [cloudlens-lab]: " PREFIX
    PREFIX="${PREFIX:-cloudlens-lab}"

    echo ""
    echo -e "  ${YELLOW}Red Hat OCM Token required for ROSA.${NC}"
    echo "  Get it at: https://console.redhat.com/openshift/token"
    echo ""
    read -rsp "  OCM API token (input hidden): " RHCS_TOKEN
    echo ""

    ENABLE_CYPERF="false"
    if prompt_yes_no "Enable CyPerf traffic generator?" "y"; then
        ENABLE_CYPERF="true"
    fi

    cat > "$TF_DIR/terraform.tfvars" << EOF
# Generated by deploy.sh
aws_profile       = "$AWS_PROFILE"
aws_region        = "$AWS_REGION"
key_pair_name     = "$KEY_PAIR"
private_key_path  = "$KEY_PATH"
deployment_prefix = "$PREFIX"

# Red Hat OCM token (sensitive - never commit this file)
rhcs_token = "$RHCS_TOKEN"

# Features
vpb_enabled     = true
rosa_enabled    = true
use_elastic_ips = true
cyperf_enabled  = $ENABLE_CYPERF
EOF

    log_success "terraform.tfvars created"
    echo ""
    echo "  Config saved to: $TF_DIR/terraform.tfvars"
    echo "  Edit to customize instance types, CIDR ranges, node counts, etc."
    echo ""
else
    log_success "terraform.tfvars found"
fi

# Parse config values
AWS_PROFILE=$(grep 'aws_profile' "$TF_DIR/terraform.tfvars" | sed 's/.*= *"\(.*\)"/\1/' | head -1)
AWS_REGION=$(grep 'aws_region' "$TF_DIR/terraform.tfvars" | sed 's/.*= *"\(.*\)"/\1/' | head -1)
DEPLOYMENT_PREFIX=$(grep 'deployment_prefix' "$TF_DIR/terraform.tfvars" | sed 's/.*= *"\(.*\)"/\1/' | head -1)
CYPERF_ENABLED=$(grep 'cyperf_enabled' "$TF_DIR/terraform.tfvars" | sed 's/.*= *//' | tr -d ' ' | head -1)
KEY_PAIR_NAME=$(grep 'key_pair_name' "$TF_DIR/terraform.tfvars" | sed 's/.*= *"\(.*\)"/\1/' | head -1)
PRIVATE_KEY=$(grep 'private_key_path' "$TF_DIR/terraform.tfvars" | sed 's/.*= *"\(.*\)"/\1/' | head -1)

# Check OCM token is set
if ! grep -q 'rhcs_token' "$TF_DIR/terraform.tfvars"; then
    log_error "rhcs_token not found in terraform.tfvars"
    echo ""
    echo "  Add this to $TF_DIR/terraform.tfvars:"
    echo '  rhcs_token = "your-token-from-console.redhat.com/openshift/token"'
    exit 1
fi

echo ""
echo "  Configuration:"
echo "    Profile:    $AWS_PROFILE"
echo "    Region:     $AWS_REGION"
echo "    Prefix:     $DEPLOYMENT_PREFIX"
echo "    Key Pair:   $KEY_PAIR_NAME"
echo "    CyPerf:     $CYPERF_ENABLED"
echo ""

# Validate AWS credentials
log_info "Validating AWS credentials..."
if aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
    log_success "AWS authenticated (Account: $ACCOUNT_ID)"
else
    log_error "AWS authentication failed for profile '$AWS_PROFILE'"
    echo ""
    echo "  Configure your AWS CLI profile:"
    echo "    aws configure --profile $AWS_PROFILE"
    echo "  Or for SSO:"
    echo "    aws sso login --profile $AWS_PROFILE"
    exit 1
fi

# Verify EC2 key pair exists
log_info "Checking EC2 key pair '$KEY_PAIR_NAME' in $AWS_REGION..."
if aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" &>/dev/null; then
    log_success "Key pair '$KEY_PAIR_NAME' found"
else
    log_error "Key pair '$KEY_PAIR_NAME' not found in $AWS_REGION"
    echo ""
    echo "  Create it: aws ec2 create-key-pair --key-name $KEY_PAIR_NAME --region $AWS_REGION --profile $AWS_PROFILE --query 'KeyMaterial' --output text > ~/.ssh/${KEY_PAIR_NAME}.pem"
    exit 1
fi

# Validate ROSA login
log_info "Validating ROSA/Red Hat login..."
if rosa whoami --profile "$AWS_PROFILE" &>/dev/null 2>&1; then
    log_success "ROSA CLI authenticated"
else
    log_warn "ROSA CLI not logged in. Attempting login with token from terraform.tfvars..."
    RHCS_TOKEN_VAL=$(grep 'rhcs_token' "$TF_DIR/terraform.tfvars" | sed 's/.*= *"\(.*\)"/\1/' | head -1)
    if [[ -n "$RHCS_TOKEN_VAL" ]]; then
        rosa login --token "$RHCS_TOKEN_VAL" 2>/dev/null && log_success "ROSA CLI authenticated" || {
            log_warn "ROSA CLI login failed. The token will still be used by Terraform via the rhcs provider."
        }
    fi
fi

# ============================================================================
# STEP 3: TERRAFORM INIT & APPLY
# ============================================================================
log_step "3/9" "Deploying Infrastructure (Terraform)"

cd "$TF_DIR"

log_info "Running terraform init..."
terraform init -input=false -upgrade 2>&1
echo ""

log_info "Running terraform plan..."
terraform plan -input=false -out=tfplan 2>&1
echo ""

echo -e "  ${YELLOW}This will create AWS resources including a ROSA cluster (costs ~\$2-3/hr).${NC}"
echo -e "  ${YELLOW}ROSA HCP cluster creation takes 15-20 minutes.${NC}"
if prompt_yes_no "Proceed with terraform apply?"; then
    log_info "Running terraform apply (this takes ~20-30 minutes for full ROSA + EC2)..."
    terraform apply -input=false tfplan 2>&1
    rm -f tfplan
    echo ""
    log_success "Infrastructure deployed"
else
    log_warn "Deployment cancelled."
    rm -f tfplan
    exit 0
fi

# ============================================================================
# STEP 4: WAIT FOR PRODUCT INITIALIZATION
# ============================================================================
log_step "4/9" "Waiting for Product Initialization"

CLMS_URL=$(terraform output -raw clms_url 2>/dev/null || echo "")
KVO_URL=$(terraform output -raw kvo_url 2>/dev/null || echo "")
CLMS_PRIVATE_IP=$(terraform output -raw clms_private_ip 2>/dev/null || echo "")
ROSA_CLUSTER=$(terraform output -raw rosa_cluster_name 2>/dev/null || echo "")

echo "  Products need time to initialize after first boot."
echo ""
echo "  ROSA cluster: $ROSA_CLUSTER"
echo ""

CLMS_HOST=$(echo "$CLMS_URL" | sed 's|https://||')
KVO_HOST=$(echo "$KVO_URL" | sed 's|https://||')

MAX_WAIT=45

# Wait for CLMS
log_info "Waiting for CLMS to be reachable (up to 15 minutes)..."
for i in $(seq 1 $MAX_WAIT); do
    if curl -sk --connect-timeout 5 "https://$CLMS_HOST" >/dev/null 2>&1; then
        log_success "CLMS is reachable: $CLMS_URL"
        break
    fi
    if [[ $i -eq $MAX_WAIT ]]; then
        log_warn "CLMS not reachable yet (still initializing). Continuing..."
    else
        echo -ne "  Waiting for CLMS... ($i/$MAX_WAIT)\r"
        sleep 20
    fi
done

# Wait for KVO
log_info "Waiting for KVO to be reachable..."
for i in $(seq 1 $MAX_WAIT); do
    if curl -sk --connect-timeout 5 "https://$KVO_HOST" >/dev/null 2>&1; then
        log_success "KVO is reachable: $KVO_URL"
        break
    fi
    if [[ $i -eq $MAX_WAIT ]]; then
        log_warn "KVO not reachable yet (still initializing). Continuing..."
    else
        echo -ne "  Waiting for KVO... ($i/$MAX_WAIT)\r"
        sleep 20
    fi
done

# Wait for ROSA cluster to be ready
if [[ -n "$ROSA_CLUSTER" ]]; then
    log_info "Checking ROSA cluster state..."
    ROSA_STATE=$(rosa describe cluster -c "$ROSA_CLUSTER" --output json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',{}).get('state','unknown'))" 2>/dev/null || echo "unknown")
    log_info "ROSA cluster state: $ROSA_STATE"

    if [[ "$ROSA_STATE" != "ready" ]]; then
        log_info "Waiting for ROSA cluster to reach 'ready' state (may take 15-20 min)..."
        for i in $(seq 1 60); do
            ROSA_STATE=$(rosa describe cluster -c "$ROSA_CLUSTER" --output json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',{}).get('state','unknown'))" 2>/dev/null || echo "unknown")
            if [[ "$ROSA_STATE" == "ready" ]]; then
                log_success "ROSA cluster is ready"
                break
            fi
            if [[ $i -eq 60 ]]; then
                log_warn "ROSA cluster not ready yet. Proceeding — it may still be provisioning."
                log_warn "Check status: rosa describe cluster -c $ROSA_CLUSTER"
            else
                echo -ne "  ROSA state: $ROSA_STATE ($i/60, ~${i}min elapsed)\r"
                sleep 30
            fi
        done
    else
        log_success "ROSA cluster is ready"
    fi
fi

# ============================================================================
# STEP 5: CONFIGURE OC FOR ROSA
# ============================================================================
log_step "5/9" "Configuring oc for ROSA"

ROSA_API_URL=$(terraform output -raw rosa_api_url 2>/dev/null || echo "")
ROSA_ADMIN_PASS=$(terraform output -raw rosa_admin_password 2>/dev/null || echo "")
ROSA_LOGIN_CMD=$(terraform output -raw rosa_login_command 2>/dev/null || echo "")

if [[ -n "$ROSA_API_URL" && -n "$ROSA_ADMIN_PASS" ]]; then
    log_info "Logging in to ROSA cluster: $ROSA_API_URL"
    oc login "$ROSA_API_URL" \
        --username cluster-admin \
        --password "$ROSA_ADMIN_PASS" \
        --insecure-skip-tls-verify=true 2>&1 || {
        log_warn "oc login failed. The cluster admin user may not be ready yet."
        log_warn "Try again in a few minutes:"
        echo "  $ROSA_LOGIN_CMD"
    }
else
    log_warn "Could not auto-detect ROSA credentials."
    echo ""
    echo "  Get the login command:"
    echo "    rosa describe admin -c $ROSA_CLUSTER"
    echo ""
fi

# Verify connectivity
if oc whoami &>/dev/null 2>&1; then
    log_success "oc connected as: $(oc whoami)"
    echo ""
    log_info "Cluster nodes:"
    oc get nodes 2>&1
fi

# ============================================================================
# STEP 6: DEPLOY OPENSHIFT WORKLOADS
# ============================================================================
log_step "6/9" "Deploying OpenShift Workloads"

if ! oc whoami &>/dev/null 2>&1; then
    log_warn "Not connected to OpenShift cluster. Skipping workload deployment."
    log_warn "Login first: $ROSA_LOGIN_CMD"
    log_warn "Then apply manifests manually: oc apply -f $MANIFESTS_DIR/"
else
    # 6a: Deploy nginx-demo (bitnami/nginx on port 8080 - OpenShift non-root)
    log_info "Deploying nginx-demo with CloudLens sensor..."

    # Build the manifest with real CLMS IP substituted
    CLOUDLENS_CFG="$MANIFESTS_DIR/cloudlens-config.yaml"
    NGINX_MANIFEST="$MANIFESTS_DIR/nginx-openshift-deployment.yaml"

    if [[ -n "$CLMS_PRIVATE_IP" ]]; then
        sed -e "s|REPLACE_WITH_CLMS_PRIVATE_IP|${CLMS_PRIVATE_IP}|g" \
            -e "s|REPLACE_WITH_VPB_INGRESS_IP||g" \
            -e "s|REPLACE_WITH_DEPLOYMENT_PREFIX|${DEPLOYMENT_PREFIX}|g" \
            "$NGINX_MANIFEST" | oc apply -f -
        log_success "nginx-demo deployed with CLMS private IP: $CLMS_PRIVATE_IP"
    else
        log_warn "CLMS private IP not detected. Applying manifest without substitution."
        log_warn "Edit $CLOUDLENS_CFG and $NGINX_MANIFEST with correct IPs, then: oc apply -f $MANIFESTS_DIR/"
        oc apply -f "$NGINX_MANIFEST" 2>&1 || true
    fi

    # 6b: Wait for nginx-demo pods
    log_info "Waiting for nginx-demo pods..."
    oc rollout status deployment/nginx-demo -n default --timeout=180s 2>&1 || \
        log_warn "nginx-demo deployment not ready yet. Check: oc get pods -n default"

    log_success "nginx-demo deployed (2 replicas)"

    # 6c: Show OpenShift Route URL
    log_info "Getting OpenShift Route URL (may take a moment)..."
    for i in $(seq 1 20); do
        NGINX_ROUTE=$(oc get route nginx-demo -n default -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
        if [[ -n "$NGINX_ROUTE" ]]; then
            log_success "nginx-demo Route: https://$NGINX_ROUTE"
            break
        fi
        echo -ne "  Waiting for Route... ($i/20)\r"
        sleep 10
    done

    if [[ -z "$NGINX_ROUTE" ]]; then
        log_warn "Route URL not ready. Check: oc get route nginx-demo -n default"
    fi
fi

# ============================================================================
# STEP 7: DEPLOY CYPERF (IF ENABLED)
# ============================================================================
if [[ "$CYPERF_ENABLED" == "true" ]]; then
    log_step "7/9" "Deploying CyPerf Traffic Generator"

    CYPERF_PUBLIC_IP=$(terraform -chdir="$TF_DIR" output -raw cyperf_controller_public_ip 2>/dev/null || echo "")
    CYPERF_PRIVATE_IP=$(terraform -chdir="$TF_DIR" output -raw cyperf_controller_private_ip 2>/dev/null || echo "")

    if [[ -z "$CYPERF_PUBLIC_IP" || "$CYPERF_PUBLIC_IP" == "CyPerf not deployed" ]]; then
        log_warn "CyPerf Controller IP not found. Skipping CyPerf deployment."
    else
        echo ""
        echo -e "  ${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${BOLD}${YELLOW}║          CyPerf License Activation Required             ║${NC}"
        echo -e "  ${BOLD}${YELLOW}╠══════════════════════════════════════════════════════════╣${NC}"
        echo -e "  ${BOLD}${YELLOW}║                                                          ║${NC}"
        echo -e "  ${BOLD}${YELLOW}║  Before CyPerf can run tests, activate your license:     ║${NC}"
        echo -e "  ${BOLD}${YELLOW}║                                                          ║${NC}"
        echo -e "  ${BOLD}${YELLOW}║  1. Open: https://${CYPERF_PUBLIC_IP}$(printf '%*s' $((25 - ${#CYPERF_PUBLIC_IP})) '')║${NC}"
        echo -e "  ${BOLD}${YELLOW}║  2. Login: admin / CyPerf&Keysight#1                     ║${NC}"
        echo -e "  ${BOLD}${YELLOW}║  3. Settings (gear) > Licensing > License Manager         ║${NC}"
        echo -e "  ${BOLD}${YELLOW}║  4. Activate licenses > paste your codes > Activate       ║${NC}"
        echo -e "  ${BOLD}${YELLOW}║                                                          ║${NC}"
        echo -e "  ${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""

        if prompt_yes_no "Have you activated the CyPerf license (or want to skip for now)?"; then
            log_info "Deploying CyPerf OpenShift agents..."
            echo ""

            if [[ -x "$SCRIPT_DIR/deploy-cyperf-openshift.sh" ]]; then
                "$SCRIPT_DIR/deploy-cyperf-openshift.sh" "$CYPERF_PRIVATE_IP" "$ROSA_CLUSTER" "$AWS_REGION" "$AWS_PROFILE" 2>&1 || {
                    log_warn "CyPerf deployment had issues. Re-run manually:"
                    echo "  ./scripts/deploy-cyperf-openshift.sh"
                }
            else
                log_warn "deploy-cyperf-openshift.sh not found or not executable."
                echo "  chmod +x ./scripts/deploy-cyperf-openshift.sh && ./scripts/deploy-cyperf-openshift.sh"
            fi
        else
            log_info "Skipping CyPerf deployment. Run later:"
            echo "  ./scripts/deploy-cyperf-openshift.sh"
        fi
    fi
else
    log_step "7/9" "CyPerf Deployment (Skipped - not enabled)"
    echo "  To enable CyPerf: set cyperf_enabled = true in terraform.tfvars"
    echo "  Then: cd terraform && terraform apply && ../scripts/deploy-cyperf-openshift.sh"
fi

# ============================================================================
# STEP 8: GENERATE DOCUMENTATION
# ============================================================================
log_step "8/9" "Generating Deployment Documentation"

cd "$TF_DIR"
log_info "Regenerating documentation with current IPs..."
terraform apply -target=module.documentation -auto-approve -input=false 2>&1
echo ""

GUIDE_PATH="$TF_DIR/generated/$DEPLOYMENT_PREFIX/$(echo "$DEPLOYMENT_PREFIX" | tr '[:lower:]' '[:upper:]')-GUIDE.md"
CREDS_PATH="$TF_DIR/generated/$DEPLOYMENT_PREFIX/credentials.txt"

if [[ -f "$GUIDE_PATH" ]]; then
    log_success "Lab guide:    $GUIDE_PATH"
fi
if [[ -f "$CREDS_PATH" ]]; then
    log_success "Credentials:  $CREDS_PATH"
fi

# ============================================================================
# STEP 9: DEPLOYMENT SUMMARY
# ============================================================================
log_step "9/9" "Deployment Complete!"

cd "$TF_DIR"

CLMS_URL=$(terraform output -raw clms_url 2>/dev/null || echo "N/A")
KVO_URL=$(terraform output -raw kvo_url 2>/dev/null || echo "N/A")
VPB_IP=$(terraform output -raw vpb_public_ip 2>/dev/null || echo "N/A")
UBUNTU_IP=$(terraform output -raw ubuntu_public_ip 2>/dev/null || echo "N/A")
WINDOWS_IP=$(terraform output -raw windows_public_ip 2>/dev/null || echo "N/A")
TOOL_LINUX_IP=$(terraform output -raw tool_linux_public_ip 2>/dev/null || echo "N/A")
TOOL_WINDOWS_IP=$(terraform output -raw tool_windows_public_ip 2>/dev/null || echo "N/A")
CYPERF_URL=$(terraform output -raw cyperf_controller_ui_url 2>/dev/null || echo "")
ROSA_CONSOLE=$(terraform output -raw rosa_console_url 2>/dev/null || echo "N/A")
ROSA_LOGIN=$(terraform output -raw rosa_login_command 2>/dev/null || echo "see terraform output rosa_login_command")

echo ""
echo -e "${BOLD}${GREEN}============================================================================${NC}"
echo -e "${BOLD}${GREEN}  CLOUDLENS OPENSHIFT VISIBILITY LAB - DEPLOYMENT COMPLETE${NC}"
echo -e "${BOLD}${GREEN}============================================================================${NC}"
echo ""
echo -e "  ${BOLD}Keysight Products${NC}"
echo "  ─────────────────────────────────────────────────────"
echo "  CLMS (CloudLens Manager):  $CLMS_URL"
echo "                             admin / Cl0udLens@dm!n"
echo "  KVO  (Vision One):         $KVO_URL"
echo "                             admin / admin"
echo "  vPB  (Packet Broker):      ssh -i $PRIVATE_KEY admin@$VPB_IP"
echo "                             admin / ixia"
if [[ -n "$CYPERF_URL" && "$CYPERF_URL" != "CyPerf not deployed" ]]; then
echo "  CyPerf Controller:         $CYPERF_URL"
echo "                             admin / CyPerf&Keysight#1"
fi
echo ""
echo -e "  ${BOLD}OpenShift / ROSA${NC}"
echo "  ─────────────────────────────────────────────────────"
echo "  Cluster name:   $ROSA_CLUSTER"
echo "  Console URL:    $ROSA_CONSOLE"
echo "  Login command:  $ROSA_LOGIN"
echo "  Namespace mgmt: oc get pods --all-namespaces"
if [[ -n "${NGINX_ROUTE:-}" ]]; then
echo ""
echo "  nginx-demo:     https://$NGINX_ROUTE"
fi
echo ""
echo -e "  ${BOLD}Workload VMs${NC}"
echo "  ─────────────────────────────────────────────────────"
echo "  Ubuntu:   ssh -i $PRIVATE_KEY ubuntu@$UBUNTU_IP"
echo "  Windows:  RDP to $WINDOWS_IP:3389 (Administrator)"
echo ""
echo -e "  ${BOLD}Tool VMs (Traffic Receivers)${NC}"
echo "  ─────────────────────────────────────────────────────"
echo "  Linux:    ssh -i $PRIVATE_KEY ubuntu@$TOOL_LINUX_IP"
echo "  Windows:  RDP to $TOOL_WINDOWS_IP:3389 (Administrator / CloudLens2024!)"
echo ""
echo -e "  ${BOLD}Generated Documentation${NC}"
echo "  ─────────────────────────────────────────────────────"
[[ -f "$GUIDE_PATH" ]] && echo "  Lab Guide:    $GUIDE_PATH"
[[ -f "$CREDS_PATH" ]] && echo "  Credentials:  $CREDS_PATH"
echo ""
echo -e "  ${BOLD}${YELLOW}NEXT STEPS:${NC}"
echo "  ─────────────────────────────────────────────────────"
echo "  1. Activate licenses in KVO: $KVO_URL"
echo "     (Settings > Product Licensing > Activate licenses)"
echo "  2. Log in to CLMS and create KVO user: $CLMS_URL"
echo "  3. Register CLMS in KVO Inventory"
echo "  4. Follow the lab guide for exercises"
echo "  5. In CloudLens Manager, create a project + sensor policy"
echo "     targeting OpenShift pods (platform=openshift tag)"
if [[ -n "$CYPERF_URL" && "$CYPERF_URL" != "CyPerf not deployed" ]]; then
echo "  6. Activate CyPerf license: $CYPERF_URL"
echo "     (Settings > Licensing > License Manager)"
fi
echo ""
echo -e "  ${BOLD}Cost Management:${NC}"
echo "    Stop all:    ./scripts/stop-all.sh  (scales ROSA to 0 + stops EC2)"
echo "    Start all:   ./scripts/start-all.sh (starts EC2 + scales ROSA to 2)"
echo "    Destroy all: ./scripts/destroy.sh   (removes all AWS resources)"
echo ""
echo -e "  ${BOLD}Useful Commands:${NC}"
echo "    oc get pods --all-namespaces"
echo "    oc get nodes"
echo "    oc get route -n default"
echo "    rosa describe cluster -c $ROSA_CLUSTER"
echo ""
echo -e "${BOLD}${GREEN}============================================================================${NC}"
echo ""
