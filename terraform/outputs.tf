# ============================================================================
# ROOT OUTPUTS
# ============================================================================

# CLMS
output "clms_url" {
  description = "CloudLens Manager UI URL"
  value       = module.lab.clms_ui_url
}

output "clms_public_ip" {
  description = "CLMS public IP"
  value       = module.lab.clms_public_ip
}

output "clms_private_ip" {
  description = "CLMS private IP"
  value       = module.lab.clms_private_ip
}

# KVO
output "kvo_url" {
  description = "Keysight Vision One UI URL"
  value       = module.lab.kvo_ui_url
}

output "kvo_public_ip" {
  description = "KVO public IP"
  value       = module.lab.kvo_public_ip
}

# vPB
output "vpb_public_ip" {
  description = "vPB management public IP"
  value       = module.lab.vpb_public_ip
}

output "vpb_interfaces" {
  description = "vPB interface IPs"
  value       = module.lab.vpb_interfaces
}

# ROSA
output "rosa_cluster_name" {
  description = "ROSA cluster name"
  value       = module.lab.rosa_cluster_name
}

output "rosa_console_url" {
  description = "OpenShift Console URL"
  value       = module.lab.rosa_console_url
}

output "rosa_api_url" {
  description = "OpenShift API URL"
  value       = module.lab.rosa_api_url
}

output "rosa_login_command" {
  description = "oc login command"
  value       = module.lab.rosa_login_command
}

output "rosa_admin_password" {
  description = "cluster-admin password"
  sensitive   = true
  value       = module.lab.rosa_admin_password
}

# Workload VMs
output "ubuntu_public_ip" {
  description = "Ubuntu workload VM public IP"
  value       = module.lab.ubuntu_1_public_ip
}

output "windows_public_ip" {
  description = "Windows workload VM public IP"
  value       = module.lab.windows_public_ip
}

# Tool VMs
output "tool_linux_public_ip" {
  description = "Linux tool VM public IP (tcpdump/tshark)"
  value       = module.lab.tool_linux_public_ip
}

output "tool_linux_private_ip" {
  description = "Linux tool VM private IP"
  value       = module.lab.tool_linux_private_ip
}

output "tool_windows_public_ip" {
  description = "Windows tool VM public IP (Wireshark)"
  value       = module.lab.tool_windows_public_ip
}

# SSH Commands
output "ssh_commands" {
  description = "SSH/RDP commands for all VMs"
  value       = module.lab.ssh_commands
}

# Deployment prefix
output "deployment_prefix" {
  description = "Deployment prefix used for all resources"
  value       = module.lab.deployment_prefix
}

# CyPerf
output "cyperf_controller_public_ip" {
  description = "CyPerf Controller public IP"
  value       = var.cyperf_enabled ? aws_eip.cyperf_controller[0].public_ip : "CyPerf not deployed"
}

output "cyperf_controller_private_ip" {
  description = "CyPerf Controller private IP"
  value       = var.cyperf_enabled ? aws_instance.cyperf_controller[0].private_ip : "CyPerf not deployed"
}

output "cyperf_controller_ui_url" {
  description = "CyPerf Controller UI URL"
  value       = var.cyperf_enabled ? "https://${aws_eip.cyperf_controller[0].public_ip}" : "CyPerf not deployed"
}

# All instance IDs
output "all_instance_ids" {
  description = "All EC2 instance IDs"
  value       = module.lab.all_instance_ids
}
