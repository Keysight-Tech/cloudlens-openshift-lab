# ============================================================================
# DOCUMENTATION GENERATOR (OpenShift edition)
# Generates deployment-specific lab guide and credentials file
# ============================================================================

locals {
  guide_filename = "${upper(var.deployment_prefix)}-GUIDE.md"
}

resource "local_file" "lab_guide" {
  filename = "${var.output_directory}/${local.guide_filename}"
  content  = <<-EOT
# ${upper(var.deployment_prefix)} - CloudLens OpenShift Visibility Lab Guide

## Deployment Summary

| Resource | Value |
|----------|-------|
| Deployment Prefix | ${var.deployment_prefix} |
| AWS Region | ${var.aws_region} |
| AWS Profile | ${var.aws_profile} |

## Keysight Products

| Product | URL | Private IP |
|---------|-----|-----------|
| CloudLens Manager (CLMS) | https://${var.clms_public_ip} | ${var.clms_private_ip} |
| Keysight Vision One (KVO) | https://${var.kvo_public_ip} | - |
${var.vpb_enabled ? "| Virtual Packet Broker (vPB) | SSH: ${var.vpb_public_ip} | ${lookup(var.vpb_interfaces, "management", "N/A")} |" : "| Virtual Packet Broker | Not deployed | - |"}

## OpenShift / ROSA

| Item | Value |
|------|-------|
| Cluster Name | ${var.rosa_cluster_name} |
| Console URL | ${var.rosa_console_url} |
| API URL | ${var.rosa_api_url} |
| Login Command | `${var.rosa_login_command}` |

## Virtual Machines

| VM | Public IP | Access |
|----|-----------|--------|
| Ubuntu Workload | ${var.ubuntu_public_ip} | `ssh -i ${var.private_key_path} ubuntu@${var.ubuntu_public_ip}` |
| Windows Workload | ${var.windows_public_ip} | RDP to ${var.windows_public_ip}:3389 |
| Linux Tool (tcpdump) | ${var.tool_linux_public_ip} | `ssh -i ${var.private_key_path} ubuntu@${var.tool_linux_public_ip}` |
| Windows Tool (Wireshark) | ${var.tool_windows_public_ip} | RDP to ${var.tool_windows_public_ip}:3389 |

${var.cyperf_enabled ? "## CyPerf\n\n| Item | Value |\n|------|-------|\n| Controller UI | https://${var.cyperf_controller_public_ip} |\n| Private IP | ${var.cyperf_controller_private_ip} |\n| Login | admin / CyPerf&Keysight#1 |" : ""}

## Quick Start

1. **Login to OpenShift:**
   ```bash
   ${var.rosa_login_command}
   ```

2. **Deploy nginx-demo:**
   ```bash
   oc apply -f kubernetes_manifests/nginx-openshift-deployment.yaml
   oc get route nginx-demo
   ```

3. **Deploy CyPerf agents:**
   ```bash
   ./scripts/deploy-cyperf-openshift.sh
   ```

4. **Monitor traffic:**
   ```bash
   oc logs -f -l app=nginx-demo -n default | grep -v kube-probe
   ```

EOT

  directory_permission = "0755"
  file_permission      = "0644"
}

resource "local_file" "credentials" {
  filename = "${var.output_directory}/credentials.txt"
  content  = <<-EOT
CloudLens OpenShift Lab Credentials - ${var.deployment_prefix}
Generated: ${timestamp()}

CLMS: https://${var.clms_public_ip}
  Username: admin
  Password: Cl0udLens@dm!n

KVO: https://${var.kvo_public_ip}
  Username: admin
  Password: admin

${var.vpb_enabled ? "vPB: SSH ${var.vpb_public_ip}\n  Username: admin\n  Password: ixia\n" : ""}

OpenShift Console: ${var.rosa_console_url}
  Username: cluster-admin
  Password: (run: terraform output -raw rosa_admin_password)

${var.cyperf_enabled ? "CyPerf: https://${var.cyperf_controller_public_ip}\n  Username: admin\n  Password: CyPerf&Keysight#1\n" : ""}
EOT

  directory_permission = "0755"
  file_permission      = "0600"
}
