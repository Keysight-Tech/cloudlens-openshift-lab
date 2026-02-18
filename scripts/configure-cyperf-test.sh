#!/bin/bash
# ============================================================================
# CONFIGURE CYPERF TEST - DUT MODE (OpenShift edition)
# ============================================================================
# Identical REST API flow to the EKS version - controller is cloud-agnostic.
# Creates a CyPerf test session with DUT mode pointing at the cyperf-proxy pod.
#
# Traffic path:
#   CyPerf Client Pod -> cyperf-proxy Pod (DUT) -> nginx-demo pods (CloudLens captures)
#
# Applications: HTTP App 1, Netflix, Youtube Chrome, ChatGPT, Discord
#
# Usage:
#   ./configure-cyperf-test.sh [CONTROLLER_PUBLIC_IP] [AWS_PROFILE] [AWS_REGION] [DUT_HOST_IP]
# ============================================================================

set -e

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

# Configuration
CONTROLLER_IP=${1:-""}
AWS_PROFILE=${2:-"${AWS_PROFILE:-cloudlens-lab}"}
AWS_REGION=${3:-"${AWS_REGION:-us-west-2}"}
DUT_HOST_IP=${4:-""}
CYPERF_USER="${CYPERF_USER:-admin}"
CYPERF_PASS="${CYPERF_PASS:-CyPerf&Keysight#1}"
SESSION_NAME="CloudLens OpenShift Lab - CyPerf DUT Mode"
PROFILE_NAME="CloudLens OpenShift DUT Traffic"

# App definitions
APPS=(
    "128|HTTP|HTTP App 1"
    "466|Netflix|Netflix"
    "292|Youtube|Youtube Chrome"
    "351|ChatGPT|ChatGPT"
    "367|Discord|Discord"
)

THROUGHPUT_VALUE=10
THROUGHPUT_UNIT="Mbps"
DURATION=600

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

get_token() {
    curl -sk "https://${CONTROLLER_IP}/auth/realms/keysight/protocol/openid-connect/token" \
        -d "grant_type=password&client_id=admin-cli&username=${CYPERF_USER}&password=$(python3 -c 'import urllib.parse; print(urllib.parse.quote("'"${CYPERF_PASS}"'"))')" \
        2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo ""
}

api_get()    { curl -sk -H "Authorization: Bearer $TOKEN" "https://${CONTROLLER_IP}$1" 2>/dev/null; }
api_post()   { curl -sk -X POST   -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$2" "https://${CONTROLLER_IP}$1" 2>/dev/null; }
api_patch()  { curl -sk -X PATCH  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$2" "https://${CONTROLLER_IP}$1" 2>/dev/null; }
api_delete() { curl -sk -X DELETE -H "Authorization: Bearer $TOKEN" "https://${CONTROLLER_IP}$1" 2>/dev/null; }

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo "============================================================================"
echo "  Configure CyPerf Test Session (OpenShift DUT Mode)"
echo "============================================================================"
echo ""

# Auto-detect controller IP
if [[ -z "$CONTROLLER_IP" ]]; then
    CONTROLLER_IP=$(terraform -chdir="$TF_DIR" output -raw cyperf_controller_public_ip 2>/dev/null || echo "")
    if [[ -z "$CONTROLLER_IP" ]]; then
        log_error "Could not auto-detect controller IP. Provide as argument: $0 <CONTROLLER_IP>"
        exit 1
    fi
fi
log_info "Controller: https://${CONTROLLER_IP}"

# Authenticate
log_info "Authenticating..."
TOKEN=$(get_token)
if [[ -z "$TOKEN" ]]; then
    log_error "Authentication failed. Check controller is running and credentials are correct."
    exit 1
fi
log_success "Authenticated"

# ============================================================================
# Check for existing session (idempotent)
# ============================================================================

EXISTING_SESSIONS=$(api_get "/api/v2/sessions")
EXISTING_COUNT=$(echo "$EXISTING_SESSIONS" | python3 -c "
import sys,json
try: print(len(json.load(sys.stdin)))
except: print(0)
" 2>/dev/null || echo "0")

if [[ "$EXISTING_COUNT" -gt 0 ]]; then
    log_info "Found $EXISTING_COUNT existing session(s). Using existing configuration."
    SESSION_ID=$(echo "$EXISTING_SESSIONS" | python3 -c "
import sys,json
try: print(json.load(sys.stdin)[0]['id'])
except: print('')
" 2>/dev/null || echo "")
    if [[ -n "$SESSION_ID" ]]; then
        log_success "Using session: $SESSION_ID"
        echo ""
        echo "  To start: Click 'Start' in CyPerf UI: https://${CONTROLLER_IP}"
        echo "  Or re-run after deleting existing sessions."
        exit 0
    fi
fi

# ============================================================================
# Create new test session
# ============================================================================

log_info "Creating new test session: '$SESSION_NAME'..."
SESSION_RESP=$(api_post "/api/v2/sessions" "{\"name\": \"${SESSION_NAME}\"}")
SESSION_ID=$(echo "$SESSION_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

if [[ -z "$SESSION_ID" ]]; then
    log_error "Failed to create session."
    echo "Response: $SESSION_RESP"
    exit 1
fi
log_success "Session created: $SESSION_ID"

# ============================================================================
# Create test configuration
# ============================================================================

log_info "Creating test config: '$PROFILE_NAME'..."
CONFIG_RESP=$(api_post "/api/v2/sessions/${SESSION_ID}/config/profiles" "{\"name\": \"${PROFILE_NAME}\"}")
PROFILE_ID=$(echo "$CONFIG_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
log_success "Profile created: $PROFILE_ID"

# ============================================================================
# Add network segments (Client and Server)
# ============================================================================

log_info "Creating network segments..."

CLIENT_SEG=$(api_post "/api/v2/sessions/${SESSION_ID}/config/profiles/${PROFILE_ID}/network-profiles" \
    '{"name": "Client Segment", "networkTags": ["Client"], "role": "client"}')
CLIENT_SEG_ID=$(echo "$CLIENT_SEG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

SERVER_SEG=$(api_post "/api/v2/sessions/${SESSION_ID}/config/profiles/${PROFILE_ID}/network-profiles" \
    '{"name": "Server Segment", "networkTags": ["Server"], "role": "server"}')
SERVER_SEG_ID=$(echo "$SERVER_SEG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

log_success "Network segments created (Client: $CLIENT_SEG_ID, Server: $SERVER_SEG_ID)"

# ============================================================================
# Configure DUT (Device Under Test) - cyperf-proxy pod IP
# ============================================================================

if [[ -n "$DUT_HOST_IP" ]]; then
    log_info "Configuring DUT: $DUT_HOST_IP..."
    api_patch "/api/v2/sessions/${SESSION_ID}/config/profiles/${PROFILE_ID}" \
        "{\"dut\": {\"enabled\": true, \"host\": \"${DUT_HOST_IP}\", \"port\": 80}}" >/dev/null
    log_success "DUT configured: $DUT_HOST_IP:80"
else
    log_warning "No DUT IP provided - configure manually in CyPerf UI"
fi

# ============================================================================
# Configure IP ranges (pod networking - OVN-Kubernetes uses class B)
# ============================================================================

log_info "Configuring IP ranges for OVN-Kubernetes pod networking..."

api_patch "/api/v2/sessions/${SESSION_ID}/config/profiles/${PROFILE_ID}/network-profiles/${CLIENT_SEG_ID}" \
    '{"ipRanges": [{"startIp": "0.0.0.0", "count": 1, "gateway": "0.0.0.0", "prefix": 32}]}' >/dev/null

api_patch "/api/v2/sessions/${SESSION_ID}/config/profiles/${PROFILE_ID}/network-profiles/${SERVER_SEG_ID}" \
    '{"ipRanges": [{"startIp": "0.0.0.0", "count": 1, "gateway": "0.0.0.0", "prefix": 32}]}' >/dev/null

log_success "IP ranges configured (auto-detected from pod)"

# ============================================================================
# Assign agents by tag
# ============================================================================

log_info "Assigning agents by tag (role:client / role:server)..."

api_patch "/api/v2/sessions/${SESSION_ID}/config/profiles/${PROFILE_ID}/network-profiles/${CLIENT_SEG_ID}" \
    '{"agentAssignment": {"byTag": {"tags": ["role:client"]}}}' >/dev/null

api_patch "/api/v2/sessions/${SESSION_ID}/config/profiles/${PROFILE_ID}/network-profiles/${SERVER_SEG_ID}" \
    '{"agentAssignment": {"byTag": {"tags": ["role:server"]}}}' >/dev/null

log_success "Agent assignment configured"

# ============================================================================
# Add applications
# ============================================================================

log_info "Adding applications..."
APP_COUNT=0
for APP_DEF in "${APPS[@]}"; do
    IFS='|' read -r RESOURCE_ID PROTOCOL DISPLAY_NAME <<< "$APP_DEF"
    RESULT=$(api_post "/api/v2/sessions/${SESSION_ID}/config/profiles/${PROFILE_ID}/application-profiles" \
        "{\"resourceId\": ${RESOURCE_ID}, \"protocol\": \"${PROTOCOL}\", \"name\": \"${DISPLAY_NAME}\"}" 2>/dev/null || echo "")
    if echo "$RESULT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        APP_COUNT=$((APP_COUNT + 1))
    fi
done
log_success "Added $APP_COUNT applications (HTTP, Netflix, YouTube, ChatGPT, Discord)"

# ============================================================================
# Set objectives (throughput + duration)
# ============================================================================

log_info "Setting test objectives (${THROUGHPUT_VALUE} ${THROUGHPUT_UNIT}, ${DURATION}s)..."
api_patch "/api/v2/sessions/${SESSION_ID}/config/profiles/${PROFILE_ID}" \
    "{\"objectives\": {\"throughput\": {\"value\": ${THROUGHPUT_VALUE}, \"unit\": \"${THROUGHPUT_UNIT}\"}, \"duration\": ${DURATION}}}" >/dev/null
log_success "Objectives configured"

# ============================================================================
# Start the test
# ============================================================================

log_info "Starting test..."
START_RESP=$(api_patch "/api/v2/sessions/${SESSION_ID}" '{"status": "running"}')
log_success "Start command sent"

echo ""
echo "============================================================================"
echo "  CyPerf Test Session Configured"
echo "============================================================================"
echo ""
echo "  Session ID:   $SESSION_ID"
echo "  DUT:          ${DUT_HOST_IP:-not set}:80"
echo "  Applications: HTTP, Netflix, YouTube Chrome, ChatGPT, Discord"
echo "  Throughput:   ${THROUGHPUT_VALUE} ${THROUGHPUT_UNIT}"
echo "  Duration:     ${DURATION}s"
echo ""
echo "  Controller UI: https://${CONTROLLER_IP}"
echo "  Login:         ${CYPERF_USER} / CyPerf&Keysight#1"
echo ""
echo "  Monitor nginx traffic:"
echo "    oc logs -f -l app=nginx-demo -n default | grep -v kube-probe"
echo ""
echo "============================================================================"
