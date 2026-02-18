# CloudLens OpenShift Visibility Lab

A complete Terraform lab environment demonstrating **Keysight CloudLens** network traffic visibility on **Red Hat OpenShift** (ROSA HCP) running in AWS.

> Parallel to the [cloudlens-k8s-lab](https://github.com/Keysight-Tech/cloudlens-k8s-lab) for EKS — same concept, fully adapted for OpenShift.

---

## Architecture

```
┌─────────────────────────────────────── AWS VPC (10.1.0.0/16) ───────────────────────────────────────┐
│                                                                                                       │
│  ┌─── Management Subnet (10.1.1.0/24) ──────────────────┐                                           │
│  │   ┌──────────────┐   ┌──────────────┐   ┌──────────┐ │                                           │
│  │   │     CLMS     │   │     KVO      │   │   vPB    │ │                                           │
│  │   │ CloudLens    │   │ Vision One   │   │ Packet   │ │                                           │
│  │   │  Manager     │   │ (Licensing)  │   │ Broker   │ │                                           │
│  │   └──────┬───────┘   └──────────────┘   └──────────┘ │                                           │
│  └──────────┼────────────────────────────────────────────┘                                           │
│             │ CloudLens API                                                                           │
│             ▼                                                                                         │
│  ┌─── ROSA Private Subnets (AZ1 + AZ2) ─────────────────────────────────────────────────────────┐  │
│  │                                                                                                 │  │
│  │  ┌──────────────────────────────────────────────────────────────────────────────────────────┐ │  │
│  │  │                           ROSA HCP Cluster (OVN-Kubernetes CNI)                          │ │  │
│  │  │                                                                                           │ │  │
│  │  │  namespace: default                    namespace: cyperf                                  │ │  │
│  │  │  ┌────────────────────────────┐        ┌─────────────────────────────────────────┐       │ │  │
│  │  │  │  nginx-demo (2 pods)       │  ◄────  │  cyperf-proxy  cyperf-agent-client      │       │ │  │
│  │  │  │  + cloudlens sensor        │   HTTP  │  (bitnami/ng)  (traffic source)         │       │ │  │
│  │  │  │  + openshift Route         │        │                cyperf-agent-server       │       │ │  │
│  │  │  └────────────┬───────────────┘        └──────────────────────────┬──────────────┘       │ │  │
│  │  │               │ VXLAN tunnel                                       │ REST API             │ │  │
│  │  └───────────────┼───────────────────────────────────────────────────┼──────────────────────┘ │  │
│  └──────────────────┼───────────────────────────────────────────────────┼────────────────────────┘  │
│                     │                                                     │                           │
│              To CLMS/vPB                                         CyPerf Controller EC2               │
│              (CloudLens tool)                                    (10.1.30.0/24 subnet)               │
│                                                                                                       │
│  ┌─── Workload Subnet ───────────────────────────────────────────────────────────────────────────┐  │
│  │   Ubuntu VM     Windows VM     RHEL VM     Linux Tool VM     Windows Tool VM                  │  │
│  └───────────────────────────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Traffic capture flow:**
1. CyPerf Client pod generates HTTP/app traffic → cyperf-proxy → nginx-demo pods
2. CloudLens sensor on nginx-demo pod captures traffic via VXLAN tunnel
3. Traffic forwarded to vPB → CloudLens tool (tcpdump VM, Wireshark VM)
4. KVO + CLMS provide full visibility management and analysis

---

## Key Differences vs EKS Lab

| Feature | EKS Lab | OpenShift Lab |
|---------|---------|---------------|
| Cluster type | AWS EKS (Kubernetes) | ROSA HCP (OpenShift) |
| CNI | AWS VPC CNI | OVN-Kubernetes |
| CLI | `kubectl` | `oc` (superset of kubectl) |
| Container security | Flexible | SCC enforcement (privileged SCC for CyPerf) |
| nginx image | `nginx:alpine` (port 80) | `bitnami/nginx` (port 8080, non-root) |
| Ingress | AWS LoadBalancer | OpenShift Route (TLS edge termination) |
| Cluster login | `aws eks update-kubeconfig` | `oc login` + htpasswd IDP |
| Required provider | `hashicorp/aws` | `hashicorp/aws` + `terraform-redhat/rhcs` |
| Additional prereq | — | Red Hat account + OCM token |

---

## Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Terraform | ≥ 1.5 | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| oc (OpenShift CLI) | ≥ 4.14 | [mirror.openshift.com](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/) |
| rosa CLI | latest | [console.redhat.com/openshift/downloads](https://console.redhat.com/openshift/downloads) |
| AWS CLI | ≥ 2.0 | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| jq | any | `brew install jq` / `apt install jq` |
| Python 3 | ≥ 3.8 | usually pre-installed |

**macOS quick install:**
```bash
brew install terraform openshift-cli awscli jq python3
# ROSA CLI (not in Homebrew):
curl -sL https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-macosx.tar.gz | tar xz -C /usr/local/bin
```

### AWS Requirements

1. **AWS account** with sufficient quota (EC2, EIP, ROSA)
2. **EC2 key pair** in your target region
3. **AWS Marketplace subscriptions:**
   - Keysight CloudLens Manager (CLMS)
   - Keysight Vision One (KVO)
   - Keysight Virtual Packet Broker (vPB)
   - Keysight CyPerf Controller *(optional)*
4. **ROSA quota** enabled for the account — run once:
   ```bash
   rosa verify quota --region us-west-2
   rosa verify permissions --region us-west-2
   ```

### Red Hat Requirements

1. **Red Hat account** at [console.redhat.com](https://console.redhat.com)
2. **ROSA enabled** for your AWS account (done in the Red Hat console)
3. **OCM API Token** — get it at: [console.redhat.com/openshift/token](https://console.redhat.com/openshift/token)

> **One-time setup per AWS account:**
> ```bash
> rosa create account-roles --hosted-cp --mode auto --yes
> ```
> Terraform will run this automatically, but you can pre-create them.

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/Keysight-Tech/cloudlens-openshift-lab.git
cd cloudlens-openshift-lab
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

```hcl
aws_profile       = "cloudlens-lab"     # your AWS CLI profile
aws_region        = "us-west-2"
key_pair_name     = "cloudlens-lab"     # existing EC2 key pair
private_key_path  = "~/.ssh/cloudlens-lab.pem"
deployment_prefix = "cloudlens-lab"
owner             = "your-name"

# Required for ROSA
rhcs_token = "eyJhbGciOiJSUzI1..."     # from console.redhat.com/openshift/token

# Enable features
vpb_enabled    = true
rosa_enabled   = true
cyperf_enabled = true   # set false to skip CyPerf
```

### 2. Deploy everything

```bash
chmod +x scripts/*.sh
./scripts/deploy.sh
```

The script handles everything:
- Validates prerequisites and credentials
- Runs `terraform apply`
- Waits for ROSA cluster to be ready
- Logs in via `oc login`
- Deploys nginx-demo with CloudLens sensor
- Deploys CyPerf agents (prompts for license activation)
- Generates lab documentation

**Total deployment time: ~25-35 minutes** (ROSA HCP cluster creation is the longest step).

### 3. Manual terraform workflow (alternative)

```bash
cd terraform
terraform init
terraform plan
terraform apply

# After cluster is ready:
eval "$(terraform output -raw rosa_login_command)"
oc apply -f ../kubernetes_manifests/nginx-openshift-deployment.yaml
```

---

## Post-Deployment Steps

### Activate Licenses

**KVO (required first):**
1. Open KVO UI: `terraform output kvo_url`
2. Login: `admin / admin`
3. Settings → Product Licensing → Activate licenses
4. Enter your KVO activation code

**CLMS:**
1. Open CLMS UI: `terraform output clms_url`
2. Login: `admin / Cl0udLens@dm!n`
3. Settings → License → Add license key

**CyPerf (if enabled):**
1. Open CyPerf UI: `terraform output cyperf_controller_ui_url`
2. Login: `admin / CyPerf&Keysight#1`
3. Settings (gear icon) → Licensing → License Manager → Activate

### Connect CLMS to KVO

1. In CLMS, go to **Administration → KVO Integration**
2. Enter the KVO private IP: `terraform output -raw kvo_public_ip` (use public IP if no VPN)
3. Create a CloudLens project and sensor policy targeting `platform=openshift`

### Configure vPB

Connect the vPB egress interface to receive CloudLens mirrored traffic:
```bash
ssh -i ~/.ssh/cloudlens-lab.pem admin@$(terraform output -raw vpb_public_ip)
# Default password: ixia
```

---

## Working with the OpenShift Cluster

### Cluster access

```bash
# Get login command
terraform output -raw rosa_login_command

# Or login directly
oc login $(terraform output -raw rosa_api_url) \
  --username cluster-admin \
  --password $(terraform output -raw rosa_admin_password) \
  --insecure-skip-tls-verify

# Verify
oc whoami
oc get nodes
```

### Key namespaces

```bash
oc get pods -n default   # nginx-demo (workload)
oc get pods -n cyperf    # CyPerf agents + proxy (after deploy-cyperf-openshift.sh)
```

### nginx-demo access

```bash
# Get the Route URL
oc get route nginx-demo -n default

# Check pod logs (CloudLens sensor output)
oc logs -f -l app=nginx-demo -n default | grep -v kube-probe
```

### OpenShift-specific patterns

```bash
# Check Security Context Constraints
oc describe scc privileged | grep -A5 Users

# CyPerf agents need privileged SCC (granted automatically by deploy script)
oc adm policy add-scc-to-user privileged -z cyperf-agent -n cyperf

# OpenShift Routes (replaces LoadBalancer Service)
oc get route -A

# Project/namespace context
oc project cyperf
oc get all
```

---

## CyPerf Traffic Generation

After deploying CyPerf agents:

```bash
# Manual test configuration
./scripts/configure-cyperf-test.sh $(terraform output -raw cyperf_controller_public_ip)

# Check agents in namespace
oc get pods -n cyperf -o wide

# Monitor nginx traffic being captured
oc logs -f -l app=nginx-demo -n default | grep -v kube-probe

# Watch CyPerf agent logs
oc logs -f cyperf-agent-client -n cyperf
oc logs -f cyperf-agent-server -n cyperf
```

**Traffic path (DUT mode):**
```
CyPerf Client Pod  →  cyperf-proxy  →  nginx-demo pods
    (source)           (DUT target)     (CloudLens taps here)
```

**Test parameters:**
- Applications: HTTP, Netflix, YouTube Chrome, ChatGPT, Discord
- Throughput: 10 Mbps
- Duration: 600 seconds (10 minutes)

---

## Lab Exercises

### Exercise 1: Verify Pod Traffic Capture

1. Access the CloudLens Manager and create a sensor policy
2. Check nginx-demo pods have the CloudLens sensor running:
   ```bash
   oc get pods -n default -o wide
   oc exec -it $(oc get pods -l app=nginx-demo -o name | head -1) -- ps aux | grep cloudlens
   ```
3. Generate HTTP traffic to the nginx-demo Route
4. Verify packet captures appear in CloudLens tool (tcpdump VM)

### Exercise 2: Run CyPerf Multi-App Traffic

1. Activate CyPerf license (see above)
2. Deploy CyPerf agents: `./scripts/deploy-cyperf-openshift.sh`
3. Start the test session in the CyPerf UI
4. Monitor traffic in CloudLens Manager — you should see HTTP, streaming, and chat traffic

### Exercise 3: Verify OVN-Kubernetes Capture

OpenShift uses OVN-Kubernetes CNI (not VPC CNI like EKS). Verify the CloudLens VXLAN tunnel works across pod CIDR `10.128.0.0/14`:

```bash
# From the Linux tool VM, capture VXLAN traffic
ssh -i ~/.ssh/cloudlens-lab.pem ubuntu@$(terraform output -raw tool_linux_public_ip)
sudo tcpdump -i any udp port 4789 -c 20
```

### Exercise 4: Scale Pods and Observe

```bash
# Scale nginx-demo and observe how CloudLens handles dynamic pod lifecycle
oc scale deployment nginx-demo --replicas=4 -n default
oc get pods -n default -w

# Scale back down
oc scale deployment nginx-demo --replicas=2 -n default
```

---

## Cost Management

### Stop the lab (save ~70% cost)

```bash
./scripts/stop-all.sh
```

This scales the ROSA machine pool to 0 (drains worker nodes) and stops all EC2 instances.

> **Note:** ROSA HCP control plane is managed by Red Hat and cannot be fully stopped. You pay a small control plane fee even when worker nodes are scaled to 0.

### Start the lab

```bash
./scripts/start-all.sh
```

Starts all EC2 instances and scales ROSA worker nodes back to 2.

### Destroy everything

```bash
./scripts/destroy.sh
```

Deletes all AWS resources (EC2, EIP, VPC) and the ROSA cluster. Prompts before ROSA account role deletion (those are shared across clusters).

### Cost estimate

| Component | Type | Cost/hr |
|-----------|------|---------|
| ROSA HCP control plane | Managed | ~$0.03/hr (fixed) |
| Worker nodes (2x) | m5.xlarge | ~$0.38/hr |
| CLMS | t3.large | ~$0.08/hr |
| KVO | t3.large | ~$0.08/hr |
| vPB | t3.xlarge | ~$0.17/hr |
| CyPerf Controller | t3.xlarge | ~$0.17/hr |
| Workload VMs | t3.medium × 3 | ~$0.12/hr |
| Tool VMs | t3.medium × 2 | ~$0.08/hr |
| **Total (approx.)** | | **~$1.10/hr** |

---

## Troubleshooting

### CyPerf agent CrashLoopBackOff

OpenShift blocks privileged containers without explicit SCC grant:

```bash
# Check the error
oc describe pod cyperf-agent-client -n cyperf | grep -A10 Events

# Re-apply the SCC grant
oc adm policy add-scc-to-user privileged -z cyperf-agent -n cyperf

# Restart the pods
oc delete pod cyperf-agent-client cyperf-agent-server -n cyperf
```

### nginx-demo pod errors (ImagePullBackOff)

The lab uses `bitnami/nginx` (not standard nginx) because OpenShift's default SCC blocks root containers. Standard `nginx:alpine` runs as root and will fail with `permission denied`:

```bash
# Verify image is bitnami/nginx
oc get deployment nginx-demo -n default -o jsonpath='{.spec.template.spec.containers[0].image}'
# Should show: bitnami/nginx:latest
```

### oc login fails after terraform apply

The cluster-admin htpasswd IDP may take a few minutes to become active:

```bash
# Check cluster status
rosa describe cluster -c $(terraform output -raw rosa_cluster_name)

# Wait for "State: ready" then try again
oc login $(terraform output -raw rosa_api_url) \
  --username cluster-admin \
  --password $(terraform output -raw rosa_admin_password) \
  --insecure-skip-tls-verify
```

### ROSA cluster stuck in "installing" state

```bash
# Check cluster events
rosa logs install -c $(terraform output -raw rosa_cluster_name) --tail 50

# Check account roles exist
rosa list account-roles | grep HCP-ROSA
```

### CloudLens sensor not capturing traffic

1. Verify the CloudLens sensor pod is running alongside nginx-demo:
   ```bash
   oc get pods -n default -o wide
   ```
2. Check CLMS private IP is reachable from the pod network (10.1.x.x vs 10.128.x.x are separate):
   ```bash
   oc exec -it $(oc get pods -l app=nginx-demo -o name | head -1) -- curl -k https://CLMS_IP
   ```
3. Verify security group on CLMS allows traffic from the ROSA worker node subnets (`10.1.50.0/24`, `10.1.51.0/24`)

### terraform destroy fails (ROSA resource)

If ROSA operator roles were not deleted:
```bash
rosa delete operator-roles --cluster $(terraform output -raw rosa_cluster_name) --mode auto --yes
terraform destroy
```

---

## File Structure

```
cloudlens-openshift-lab/
├── README.md                          # This file
├── CREDENTIALS.md                     # Credential reference card
├── .gitignore
│
├── terraform/
│   ├── providers.tf                   # AWS + rhcs + null + tls providers
│   ├── variables.tf                   # All variables (with defaults)
│   ├── main.tf                        # Root module: calls rosa-lab + documentation
│   ├── outputs.tf                     # All output values
│   ├── cyperf.tf                      # CyPerf Controller EC2 + auto-deploy trigger
│   └── terraform.tfvars.example       # Template — copy to terraform.tfvars
│
├── modules/
│   ├── rosa-lab/                      # ROSA cluster + Keysight products
│   │   ├── main.tf                    # AMI maps, locals, data sources
│   │   ├── variables.tf
│   │   ├── vpc.tf                     # VPC, subnets (with ROSA tags), NAT gateways
│   │   ├── rosa.tf                    # ROSA HCP cluster, machine pool, identity provider
│   │   ├── security_groups.tf         # Security groups (ROSA-aware rules)
│   │   ├── keysight_products.tf       # CLMS, KVO, vPB EC2 instances
│   │   ├── workload_vms.tf            # Ubuntu, Windows, RHEL VMs
│   │   ├── tool_vms.tf                # Linux tcpdump, Windows Wireshark
│   │   ├── elastic_ips.tf             # EIPs for all public-facing instances
│   │   └── outputs.tf
│   │
│   └── documentation/                 # Auto-generated lab guide + credentials
│       ├── main.tf
│       └── variables.tf
│
├── kubernetes_manifests/
│   ├── README.md                      # OpenShift manifest guide
│   ├── nginx-openshift-deployment.yaml # nginx-demo (bitnami/nginx) + Route
│   ├── cloudlens-config.yaml          # CloudLens sensor ConfigMap (update IPs)
│   ├── cyperf-agent-client.yaml       # CyPerf client agent pod
│   └── cyperf-agent-server.yaml       # CyPerf server agent pod
│
└── scripts/
    ├── deploy.sh                      # Main deployment orchestrator (this repo)
    ├── deploy-cyperf-openshift.sh     # CyPerf agent deployment (OpenShift-specific)
    ├── configure-cyperf-test.sh       # CyPerf test session via REST API
    ├── destroy.sh                     # Full cleanup
    ├── start-all.sh                   # Start EC2 + scale ROSA workers up
    └── stop-all.sh                    # Stop EC2 + scale ROSA workers to 0
```

---

## Default Credentials

| Product | URL | Username | Password |
|---------|-----|----------|----------|
| CLMS (CloudLens Manager) | `terraform output clms_url` | admin | Cl0udLens@dm!n |
| KVO (Vision One) | `terraform output kvo_url` | admin | admin |
| vPB (Packet Broker) | SSH to `vpb_public_ip` | admin | ixia |
| CyPerf Controller | `terraform output cyperf_controller_ui_url` | admin | CyPerf&Keysight#1 |
| OpenShift cluster-admin | `terraform output rosa_api_url` | cluster-admin | `terraform output rosa_admin_password` |
| Ubuntu VM | SSH to `ubuntu_public_ip` | ubuntu | SSH key |
| Windows VM | RDP to `windows_public_ip` | Administrator | CloudLens2024! |
| Linux Tool VM | SSH to `tool_linux_public_ip` | ubuntu | SSH key |
| Windows Tool VM | RDP to `tool_windows_public_ip` | Administrator | CloudLens2024! |

> **Change default passwords** on CLMS, KVO, and vPB immediately after first login in production environments.

---

## Related Resources

- [cloudlens-k8s-lab](https://github.com/Keysight-Tech/cloudlens-k8s-lab) — EKS version of this lab
- [ROSA HCP Documentation](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-sts-creating-a-cluster-quickly.html)
- [Terraform RHCS Provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs)
- [OpenShift Security Context Constraints](https://docs.openshift.com/container-platform/4.14/authentication/managing-security-context-constraints.html)
- [Keysight CloudLens Documentation](https://support.ixiacom.com/cloudlens)
