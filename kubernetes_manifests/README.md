# Kubernetes Manifests - CloudLens OpenShift Visibility Lab

This directory contains OpenShift-specific manifests for the CloudLens visibility lab.

## OpenShift vs EKS - Key Differences

| Aspect | EKS | OpenShift (ROSA) |
|--------|-----|-----------------|
| CLI | `kubectl` | `oc` (superset of kubectl) |
| External access | LoadBalancer Service | Route (built-in ingress controller) |
| Security | Pod Security Admission | Security Context Constraints (SCC) |
| Container ports | Any port | Port >= 1024 by default (non-root) |
| Nginx image | Standard `nginx:alpine` | `bitnami/nginx` (runs as non-root) |
| CyPerf agents | `kubectl` apply | `oc` apply + SCC grant |

## Prerequisites

1. ROSA cluster deployed and running
2. `oc` CLI installed: https://console.redhat.com/openshift/downloads
3. Logged in: `oc login <api-url> --username cluster-admin --password <password>`
4. CyPerf Controller deployed (if using CyPerf)

## Step 1: Deploy nginx-demo

```bash
oc apply -f nginx-openshift-deployment.yaml

# Verify pods are running
oc get pods -l app=nginx-demo

# Get the Route URL (external access)
oc get route nginx-demo
```

The Route URL is automatically assigned by OpenShift's ingress controller. No LoadBalancer configuration needed.

## Step 2: Configure CloudLens

### 2.1 Get CLMS private IP
```bash
terraform -chdir=../terraform output clms_private_ip
# Returns the private IP assigned to your CLMS instance (e.g. 10.1.1.x)
```

### 2.2 Update cloudlens-config.yaml
```bash
# macOS:
sed -i '' 's/REPLACE_WITH_CLMS_PRIVATE_IP/<YOUR_CLMS_IP>/g' cloudlens-config.yaml
sed -i '' 's/REPLACE_WITH_VPB_INGRESS_IP/<YOUR_VPB_IP>/g' cloudlens-config.yaml
sed -i '' 's/REPLACE_WITH_DEPLOYMENT_PREFIX/<YOUR_PREFIX>/g' cloudlens-config.yaml

# Linux:
sed -i 's/REPLACE_WITH_CLMS_PRIVATE_IP/<YOUR_CLMS_IP>/g' cloudlens-config.yaml
sed -i 's/REPLACE_WITH_VPB_INGRESS_IP/<YOUR_VPB_IP>/g' cloudlens-config.yaml
sed -i 's/REPLACE_WITH_DEPLOYMENT_PREFIX/<YOUR_PREFIX>/g' cloudlens-config.yaml

oc apply -f cloudlens-config.yaml
```

### 2.3 Get CLMS Project Key
1. Open CLMS UI: `https://<clms_public_ip>` (admin / Cl0udLens@dm!n)
2. Go to **Projects → Create Project**
3. Copy the project key (UUID format)

### 2.4 Update nginx manifest with project key
```bash
# macOS:
sed -i '' 's/REPLACE_WITH_CLMS_PROJECT_KEY/<YOUR_PROJECT_KEY>/g' nginx-openshift-deployment.yaml

# Linux:
sed -i 's/REPLACE_WITH_CLMS_PROJECT_KEY/<YOUR_PROJECT_KEY>/g' nginx-openshift-deployment.yaml

oc apply -f nginx-openshift-deployment.yaml
```

## Step 3: Deploy CyPerf Agents (automated)

The automated script handles all OpenShift-specific setup:

```bash
../scripts/deploy-cyperf-openshift.sh
```

What it does:
1. Logs in to ROSA via `oc login`
2. Creates `cyperf` namespace
3. Creates `cyperf-agent` ServiceAccount
4. Grants `privileged` SCC (required for NET_ADMIN/NET_RAW)
5. Deploys cyperf-proxy pointing at nginx-demo
6. Deploys client and server agent pods
7. Configures the CyPerf test session via REST API

### Manual SCC Grant (if needed)
```bash
oc create namespace cyperf --dry-run=client -o yaml | oc apply -f -
oc create sa cyperf-agent -n cyperf
oc adm policy add-scc-to-user privileged -z cyperf-agent -n cyperf
```

## Step 4: Monitor Traffic

```bash
# Stream nginx logs (all traffic, excluding health checks)
oc logs -f -l app=nginx-demo -n default | grep -v kube-probe

# With pod prefix to see which pod
oc logs -f -l app=nginx-demo -n default --prefix | grep -v kube-probe

# CyPerf agent status
oc get pods -n cyperf -o wide
oc logs cyperf-agent-client -n cyperf --tail=50

# Check Route URL
oc get route nginx-demo -n default
```

## Troubleshooting

### Pod stuck in `CreateContainerConfigError`
The CyPerf agent needs the privileged SCC:
```bash
oc describe pod cyperf-agent-client -n cyperf
# Look for: unable to validate against any security context constraint

# Fix:
oc adm policy add-scc-to-user privileged -z cyperf-agent -n cyperf
oc delete pod cyperf-agent-client cyperf-agent-server -n cyperf
# Then re-apply manifests
```

### nginx pod stuck in `CrashLoopBackOff`
OpenShift enforces non-root. The standard `nginx:alpine` image tries to bind port 80 as root.
Use `bitnami/nginx` (already in the manifest) which runs on port 8080 as non-root.

### Route not accessible
```bash
oc get route nginx-demo -n default
# Check TLS and status
oc describe route nginx-demo -n default
```

### oc login failing
```bash
# Get credentials from terraform
terraform -chdir=../terraform output rosa_login_command
terraform -chdir=../terraform output -raw rosa_admin_password
```
