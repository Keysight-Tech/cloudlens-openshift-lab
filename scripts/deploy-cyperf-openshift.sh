#!/bin/bash
# ============================================================================
# DEPLOY CYPERF OPENSHIFT AGENTS
# ============================================================================
# Deploys CyPerf client and server agents as pods in OpenShift/ROSA.
#
# OpenShift-specific steps vs EKS:
#   1. Uses 'oc' CLI instead of 'kubectl' for cluster login
#   2. Creates ServiceAccount 'cyperf-agent' in cyperf namespace
#   3. Grants 'privileged' SCC to the ServiceAccount (required for NET_ADMIN)
#   4. Deploys cyperf-proxy (nginx -> nginx-demo service)
#   5. Deploys client + server agent pods
#   6. Configures CyPerf test session via REST API
#
# Traffic Path (same as EKS):
#   CyPerf Client Pod -> cyperf-proxy Pod (DUT) -> nginx-demo pods (CloudLens captures)
#
# Prerequisites:
#   - CyPerf Controller VM deployed (terraform apply with cyperf_enabled=true)
#   - ROSA cluster running with nginx-demo pods deployed
#   - oc CLI installed
#
# Usage:
#   ./deploy-cyperf-openshift.sh [CONTROLLER_PRIVATE_IP] [CLUSTER_NAME] [AWS_REGION] [AWS_PROFILE]
#   ./deploy-cyperf-openshift.sh              # Auto-detect all
#   ./deploy-cyperf-openshift.sh 10.1.30.103  # Explicit controller IP
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="$BASE_DIR/kubernetes_manifests"
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

# Configuration - env vars take priority, then args, then auto-detect
CONTROLLER_PRIVATE_IP=${CYPERF_CONTROLLER_PRIVATE_IP:-${1:-""}}
CLUSTER_NAME=${CYPERF_ROSA_CLUSTER_NAME:-${2:-""}}
AWS_REGION=${CYPERF_AWS_REGION:-${3:-"us-west-2"}}
AWS_PROFILE=${CYPERF_AWS_PROFILE:-${4:-"cloudlens-lab"}}
CONTROLLER_PUBLIC_IP_ENV=${CYPERF_CONTROLLER_PUBLIC_IP:-""}
DEPLOYMENT_PREFIX_ENV=${CYPERF_DEPLOYMENT_PREFIX:-""}
NAMESPACE="cyperf"
AGENT_IMAGE="public.ecr.aws/keysight/cyperf-agent:release7.0"

DEPLOYMENT_PREFIX="${DEPLOYMENT_PREFIX_ENV}"
if [[ -z "$DEPLOYMENT_PREFIX" ]]; then
    DEPLOYMENT_PREFIX=$(terraform -chdir="$TF_DIR" output -raw deployment_prefix 2>/dev/null || echo "cloudlens-lab")
fi

echo ""
echo "============================================================================"
echo "  Deploy CyPerf OpenShift Agents"
echo "============================================================================"
echo ""

# ============================================================================
# STEP 1: Auto-detect controller IPs
# ============================================================================

if [[ -z "$CONTROLLER_PRIVATE_IP" ]]; then
    log_info "Auto-detecting CyPerf Controller private IP..."
    CONTROLLER_PRIVATE_IP=$(terraform -chdir="$TF_DIR" output -raw cyperf_controller_private_ip 2>/dev/null || echo "")
    if [[ -z "$CONTROLLER_PRIVATE_IP" ]]; then
        log_error "Could not auto-detect CyPerf Controller private IP."
        log_error "Provide it explicitly: $0 <CONTROLLER_PRIVATE_IP>"
        exit 1
    fi
fi
log_success "Controller private IP: $CONTROLLER_PRIVATE_IP"

CONTROLLER_PUBLIC_IP="${CONTROLLER_PUBLIC_IP_ENV}"
if [[ -z "$CONTROLLER_PUBLIC_IP" ]]; then
    CONTROLLER_PUBLIC_IP=$(terraform -chdir="$TF_DIR" output -raw cyperf_controller_public_ip 2>/dev/null || echo "")
fi

CONTROLLER_API_IP="$CONTROLLER_PUBLIC_IP"
if [[ -z "$CONTROLLER_API_IP" ]]; then
    CONTROLLER_API_IP="$CONTROLLER_PRIVATE_IP"
fi

# Auto-detect ROSA cluster name
if [[ -z "$CLUSTER_NAME" ]]; then
    CLUSTER_NAME=$(terraform -chdir="$TF_DIR" output -raw rosa_cluster_name 2>/dev/null || echo "${DEPLOYMENT_PREFIX}-rosa")
fi
log_success "ROSA cluster: $CLUSTER_NAME"

# ============================================================================
# STEP 2: Login to ROSA cluster via oc
# ============================================================================

log_info "Logging in to ROSA cluster..."

ROSA_API_URL=$(terraform -chdir="$TF_DIR" output -raw rosa_api_url 2>/dev/null || echo "")
ROSA_ADMIN_PASS=$(terraform -chdir="$TF_DIR" output -raw rosa_admin_password 2>/dev/null || echo "")

if [[ -n "$ROSA_API_URL" && -n "$ROSA_ADMIN_PASS" ]]; then
    oc login "$ROSA_API_URL" \
        --username cluster-admin \
        --password "$ROSA_ADMIN_PASS" \
        --insecure-skip-tls-verify=true 2>/dev/null
    log_success "Logged in to ROSA cluster"
else
    log_warning "Could not auto-detect ROSA credentials from terraform output."
    log_warning "Login manually with: oc login <api-url> --username cluster-admin --password <password>"
    log_warning "Then re-run this script."
    # Try current context
    if ! oc whoami &>/dev/null; then
        log_error "No active oc session. Please login first."
        exit 1
    fi
    log_info "Using existing oc session: $(oc whoami)"
fi

# ============================================================================
# STEP 3: Clean up existing CyPerf resources
# ============================================================================

echo ""
log_info "Cleaning up existing CyPerf resources..."
oc delete pod,svc,deployment,configmap,endpoints,serviceaccount --all -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
log_success "Namespace cleanup complete"

sleep 5
oc wait --for=delete pod -l app=cyperf-agent -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
oc wait --for=delete pod -l app=cyperf-proxy -n "$NAMESPACE" --timeout=60s 2>/dev/null || true

# ============================================================================
# STEP 4: Wait for CyPerf Controller to be ready
# ============================================================================

echo ""
log_info "Waiting for CyPerf Controller to be ready..."

MAX_RETRIES=30
RETRY_INTERVAL=20
CONTROLLER_READY=false

for attempt in $(seq 1 $MAX_RETRIES); do
    if curl -sk --connect-timeout 10 "https://${CONTROLLER_API_IP}" >/dev/null 2>&1; then
        CONTROLLER_READY=true
        break
    fi
    if [[ $attempt -eq 1 ]]; then
        log_warning "Controller not reachable yet. Normal for fresh deploys (~10 min startup)."
    fi
    echo -e "  Attempt $attempt/$MAX_RETRIES - retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

if [[ "$CONTROLLER_READY" != "true" ]]; then
    log_error "Cannot reach CyPerf Controller at https://${CONTROLLER_API_IP}"
    exit 1
fi
log_success "Controller is reachable"

# Accept EULA
log_info "Checking EULA status..."
EULA_STATUS=$(curl -sk "https://${CONTROLLER_API_IP}/eula/v1/eula" 2>/dev/null || echo "[]")
if echo "$EULA_STATUS" | grep -q '"accepted":false'; then
    curl -sk "https://${CONTROLLER_API_IP}/eula/v1/eula/CyPerf" \
        -X POST -H "Content-Type: application/json" -d '{"accepted": true}' >/dev/null 2>&1
    log_success "EULA accepted"
    sleep 3
else
    log_info "EULA already accepted"
fi

# Wait for auth
log_info "Waiting for controller authentication (Keycloak)..."

get_token() {
    curl -sk "https://${CONTROLLER_API_IP}/auth/realms/keysight/protocol/openid-connect/token" \
        -d "grant_type=password&client_id=admin-cli&username=admin&password=$(python3 -c 'import urllib.parse; print(urllib.parse.quote("CyPerf&Keysight#1"))')" \
        2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo ""
}

AUTH_READY=false
for attempt in $(seq 1 30); do
    TOKEN=$(get_token || echo "")
    if [[ -n "$TOKEN" ]]; then
        AUTH_READY=true
        break
    fi
    echo -e "  Auth attempt $attempt/30 - retrying in 20s..."
    sleep 20
done

if [[ "$AUTH_READY" != "true" ]]; then
    log_error "Controller auth not ready. Check https://${CONTROLLER_API_IP}"
    exit 1
fi
log_success "Controller authentication ready"

# ============================================================================
# STEP 5: Clean stale agent registrations
# ============================================================================

echo ""
log_info "Cleaning stale agent registrations..."

TOKEN=$(get_token || echo "")
if [[ -n "$TOKEN" ]]; then
    SESSIONS=$(curl -sk -H "Authorization: Bearer $TOKEN" "https://${CONTROLLER_API_IP}/api/v2/sessions" 2>/dev/null)
    SESSION_IDS=$(echo "$SESSIONS" | python3 -c "
import sys,json
try:
    for s in json.load(sys.stdin): print(s['id'])
except: pass
" 2>/dev/null)
    if [[ -n "$SESSION_IDS" ]]; then
        while IFS= read -r sid; do
            [[ -n "$sid" ]] && curl -sk -X DELETE -H "Authorization: Bearer $TOKEN" \
                "https://${CONTROLLER_API_IP}/api/v2/sessions/${sid}" >/dev/null 2>&1
        done <<< "$SESSION_IDS"
        log_success "Existing sessions deleted"
    fi

    AGENT_IDS=$(curl -sk -H "Authorization: Bearer $TOKEN" "https://${CONTROLLER_API_IP}/api/v2/agents" 2>/dev/null | python3 -c "
import sys,json
try:
    for a in json.load(sys.stdin): print(a.get('id',''))
except: pass
" 2>/dev/null)
    if [[ -n "$AGENT_IDS" ]]; then
        while IFS= read -r aid; do
            [[ -n "$aid" ]] && curl -sk -X DELETE -H "Authorization: Bearer $TOKEN" \
                "https://${CONTROLLER_API_IP}/api/v2/agents/${aid}" >/dev/null 2>&1
        done <<< "$AGENT_IDS"
        log_success "Stale agent registrations cleaned"
    fi
fi

# ============================================================================
# STEP 6: Create cyperf namespace + ServiceAccount + SCC grant
# ============================================================================

echo ""
log_info "Creating cyperf namespace and granting privileged SCC..."

oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f - 2>/dev/null

# Create ServiceAccount for CyPerf agents (required for SCC grant)
cat <<SAEOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cyperf-agent
  namespace: $NAMESPACE
SAEOF

# Grant privileged SCC - required for NET_ADMIN, IPC_LOCK, NET_RAW capabilities
# OpenShift blocks these by default via SCCs
oc adm policy add-scc-to-user privileged \
    -z cyperf-agent \
    -n "$NAMESPACE" 2>/dev/null || true
log_success "ServiceAccount 'cyperf-agent' created with privileged SCC"

# ============================================================================
# STEP 7: Deploy cyperf-proxy (nginx -> nginx-demo)
# ============================================================================

echo ""
log_info "Deploying cyperf-proxy..."

UPSTREAM_SERVERS=""
FOUND_NS=""
for NS in default $(oc get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    SVC_NAME=$(oc get svc -n "$NS" -o name 2>/dev/null | grep -E "nginx-demo|nginx-service" | head -1 | sed 's|service/||')
    if [[ -n "$SVC_NAME" ]]; then
        UPSTREAM_SERVERS="${UPSTREAM_SERVERS}        server ${SVC_NAME}.${NS}.svc.cluster.local:80;\n"
        FOUND_NS="$NS"
    fi
done

if [[ -z "$UPSTREAM_SERVERS" ]]; then
    log_warning "No nginx-demo service found. Using placeholder - deploy nginx-demo first."
    UPSTREAM_SERVERS="        server nginx-demo.default.svc.cluster.local:80;\n"
    FOUND_NS="default (placeholder)"
fi

log_info "Proxy upstream: $FOUND_NS"

cat <<PROXYEOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cyperf-proxy-config
  namespace: $NAMESPACE
data:
  default.conf: |
    upstream backend {
$(echo -e "$UPSTREAM_SERVERS")    }
    server {
        listen 8080;
        location / {
            proxy_pass http://backend;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
        location /health {
            return 200 'healthy';
        }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cyperf-proxy
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cyperf-proxy
  template:
    metadata:
      labels:
        app: cyperf-proxy
    spec:
      containers:
      - name: nginx
        image: bitnami/nginx:latest
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: config
          mountPath: /opt/bitnami/nginx/conf/server_blocks
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 500m
            memory: 128Mi
      volumes:
      - name: config
        configMap:
          name: cyperf-proxy-config
---
apiVersion: v1
kind: Service
metadata:
  name: cyperf-proxy
  namespace: $NAMESPACE
spec:
  type: ClusterIP
  selector:
    app: cyperf-proxy
  ports:
  - port: 80
    targetPort: 8080
PROXYEOF

log_success "cyperf-proxy deployed"

oc rollout status deployment/cyperf-proxy -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

PROXY_POD_IP=$(oc get pods -n "$NAMESPACE" -l app=cyperf-proxy -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")
if [[ -z "$PROXY_POD_IP" ]]; then
    PROXY_POD_IP=$(oc get svc cyperf-proxy -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
fi
log_success "Proxy pod IP (DUT target): $PROXY_POD_IP"

# ============================================================================
# STEP 8: Deploy CyPerf agent pods
# ============================================================================

echo ""
log_info "Deploying CyPerf agent pods (image: $AGENT_IMAGE)..."

sed -e "s|\${CONTROLLER_PRIVATE_IP}|${CONTROLLER_PRIVATE_IP}|g" \
    -e "s|\${CYPERF_AGENT_IMAGE}|${AGENT_IMAGE}|g" \
    "$MANIFESTS_DIR/cyperf-agent-client.yaml" | oc apply -f -
log_success "Client agent pod created"

sed -e "s|\${CONTROLLER_PRIVATE_IP}|${CONTROLLER_PRIVATE_IP}|g" \
    -e "s|\${CYPERF_AGENT_IMAGE}|${AGENT_IMAGE}|g" \
    "$MANIFESTS_DIR/cyperf-agent-server.yaml" | oc apply -f -
log_success "Server agent pod created"

# ============================================================================
# STEP 9: Wait for pods to be ready
# ============================================================================

echo ""
log_info "Waiting for CyPerf agent pods to start..."
oc wait --for=condition=Ready pod/cyperf-agent-client -n "$NAMESPACE" --timeout=300s 2>/dev/null || {
    log_warning "Client pod not ready yet."
    oc describe pod cyperf-agent-client -n "$NAMESPACE" 2>/dev/null | tail -20
}

oc wait --for=condition=Ready pod/cyperf-agent-server -n "$NAMESPACE" --timeout=300s 2>/dev/null || {
    log_warning "Server pod not ready yet."
    oc describe pod cyperf-agent-server -n "$NAMESPACE" 2>/dev/null | tail -20
}

echo ""
log_info "Pod status:"
oc get pods -n "$NAMESPACE" -o wide

# ============================================================================
# STEP 10: Verify agent registration
# ============================================================================

echo ""
log_info "Waiting for agents to register with controller..."

AGENTS_READY=false
for attempt in $(seq 1 20); do
    TOKEN=$(get_token || echo "")
    if [[ -n "$TOKEN" ]]; then
        AGENT_COUNT=$(curl -sk -H "Authorization: Bearer $TOKEN" \
            "https://${CONTROLLER_API_IP}/api/v2/agents" 2>/dev/null | python3 -c "
import sys,json
agents = json.load(sys.stdin)
tagged = [a for a in agents if any('role' in str(t) for t in a.get('AgentTags',[]))]
print(len(tagged))
" 2>/dev/null || echo "0")

        if [[ "$AGENT_COUNT" -ge 2 ]]; then
            AGENTS_READY=true
            log_success "Both agents registered ($AGENT_COUNT agents with role tags)"
            break
        fi
    fi
    echo -e "  Attempt $attempt/20 - ${AGENT_COUNT:-0}/2 agents registered, waiting 15s..."
    sleep 15
done

if [[ "$AGENTS_READY" != "true" ]]; then
    log_warning "Not all agents registered yet. Check the CyPerf Controller UI: https://$CONTROLLER_API_IP"
fi

# ============================================================================
# STEP 11: Configure CyPerf test session
# ============================================================================

echo ""
log_info "Configuring CyPerf test session (DUT = $PROXY_POD_IP)..."

if [[ -n "$CONTROLLER_PUBLIC_IP" && -n "$PROXY_POD_IP" ]]; then
    "$SCRIPT_DIR/configure-cyperf-test.sh" "$CONTROLLER_PUBLIC_IP" "$AWS_PROFILE" "$AWS_REGION" "$PROXY_POD_IP"
elif [[ -n "$CONTROLLER_PUBLIC_IP" ]]; then
    "$SCRIPT_DIR/configure-cyperf-test.sh" "$CONTROLLER_PUBLIC_IP" "$AWS_PROFILE" "$AWS_REGION"
else
    log_warning "Cannot auto-configure test session. Configure manually at: https://<controller-ip>"
fi

# ============================================================================
# STEP 12: iptables fixer (background)
# OVN-Kubernetes may also trigger INPUT DROP - same fix as EKS
# ============================================================================

echo ""
log_info "Starting iptables fixer (background, 15 min)..."
(for i in $(seq 1 180); do
    oc exec -n "$NAMESPACE" cyperf-agent-client -- iptables-nft -P INPUT ACCEPT 2>/dev/null
    oc exec -n "$NAMESPACE" cyperf-agent-server -- iptables-nft -P INPUT ACCEPT 2>/dev/null
    sleep 5
done) &
IPTABLES_FIXER_PID=$!
log_success "iptables fixer PID: $IPTABLES_FIXER_PID"

# ============================================================================
# STATUS REPORT
# ============================================================================

CLIENT_POD_IP=$(oc get pod cyperf-agent-client -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "pending")
SERVER_POD_IP=$(oc get pod cyperf-agent-server -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "pending")

echo ""
echo "============================================================================"
echo "  CyPerf OpenShift Agent Deployment Complete"
echo "============================================================================"
echo ""
echo "  Agent Pods (namespace: $NAMESPACE):"
echo "    Client: cyperf-agent-client (IP: $CLIENT_POD_IP)"
echo "    Server: cyperf-agent-server (IP: $SERVER_POD_IP)"
echo ""
echo "  Proxy (ClusterIP):"
echo "    cyperf-proxy pod IP: $PROXY_POD_IP (DUT target)"
echo "    Routes to nginx-demo in $FOUND_NS"
echo ""
echo "  Traffic Path:"
echo "    CyPerf Client Pod ($CLIENT_POD_IP)"
echo "      -> cyperf-proxy ($PROXY_POD_IP)"
echo "      -> nginx-demo pods (CloudLens captures here)"
echo ""
echo "  Controller UI: https://$CONTROLLER_API_IP"
echo "  Login:         admin / CyPerf&Keysight#1"
echo ""
echo "  Monitor:"
echo "    oc get pods -n $NAMESPACE -o wide"
echo "    oc logs cyperf-agent-client -n $NAMESPACE --tail=50"
echo "    oc logs -f -l app=nginx-demo -n default | grep -v kube-probe"
echo ""
echo "  Cleanup:"
echo "    oc delete pod,svc,deployment,configmap,sa --all -n $NAMESPACE"
echo ""
echo "============================================================================"
