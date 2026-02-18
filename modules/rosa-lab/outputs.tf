# ============================================================================
# ROSA-LAB MODULE OUTPUTS
# ============================================================================

output "deployment_prefix" {
  description = "Deployment prefix for this lab"
  value       = var.deployment_prefix
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

# CLMS
output "clms_public_ip" {
  description = "CLMS public IP"
  value       = var.use_elastic_ips ? aws_eip.clms[0].public_ip : aws_instance.clms.public_ip
}

output "clms_private_ip" {
  description = "CLMS private IP"
  value       = aws_instance.clms.private_ip
}

output "clms_instance_id" {
  description = "CLMS instance ID"
  value       = aws_instance.clms.id
}

output "clms_ui_url" {
  description = "CLMS UI URL"
  value       = var.use_elastic_ips ? "https://${aws_eip.clms[0].public_ip}" : "https://${aws_instance.clms.public_ip}"
}

# KVO
output "kvo_public_ip" {
  description = "KVO public IP"
  value       = var.use_elastic_ips ? aws_eip.kvo[0].public_ip : aws_instance.kvo.public_ip
}

output "kvo_private_ip" {
  description = "KVO private IP"
  value       = aws_instance.kvo.private_ip
}

output "kvo_instance_id" {
  description = "KVO instance ID"
  value       = aws_instance.kvo.id
}

output "kvo_ui_url" {
  description = "KVO UI URL"
  value       = var.use_elastic_ips ? "https://${aws_eip.kvo[0].public_ip}" : "https://${aws_instance.kvo.public_ip}"
}

# vPB
output "vpb_public_ip" {
  description = "vPB management public IP"
  value       = var.vpb_enabled && var.use_elastic_ips ? aws_eip.vpb[0].public_ip : "vPB not deployed or no EIP"
}

output "vpb_interfaces" {
  description = "vPB interface IPs"
  value = var.vpb_enabled ? {
    management = aws_network_interface.vpb_management[0].private_ip
    ingress    = aws_network_interface.vpb_ingress[0].private_ip
    egress     = aws_network_interface.vpb_egress[0].private_ip
  } : { management = "N/A", ingress = "N/A", egress = "N/A" }
}

# Workload VMs
output "ubuntu_1_public_ip" {
  description = "Ubuntu workload VM 1 public IP"
  value       = var.ubuntu_workload_enabled ? (var.use_elastic_ips && length(aws_eip.tapped_ubuntu_1) > 0 ? aws_eip.tapped_ubuntu_1[0].public_ip : aws_instance.tapped_ubuntu_1[0].public_ip) : "Ubuntu not deployed"
}

output "ubuntu_1_private_ip" {
  description = "Ubuntu workload VM 1 private IP"
  value       = var.ubuntu_workload_enabled ? aws_instance.tapped_ubuntu_1[0].private_ip : "Ubuntu not deployed"
}

output "windows_public_ip" {
  description = "Windows workload VM public IP"
  value       = var.use_elastic_ips ? aws_eip.tapped_windows[0].public_ip : aws_instance.tapped_windows.public_ip
}

output "windows_private_ip" {
  description = "Windows workload VM private IP"
  value       = aws_instance.tapped_windows.private_ip
}

output "windows_password_data" {
  description = "Windows VM encrypted password data"
  sensitive   = true
  value       = aws_instance.tapped_windows.password_data
}

# Tool VMs
output "tool_linux_public_ip" {
  description = "Linux Tool VM public IP"
  value       = var.use_elastic_ips ? aws_eip.tool[0].public_ip : aws_instance.tool.public_ip
}

output "tool_linux_private_ip" {
  description = "Linux Tool VM private IP"
  value       = aws_instance.tool.private_ip
}

output "tool_windows_public_ip" {
  description = "Windows Tool VM public IP"
  value       = var.use_elastic_ips ? aws_eip.tool_windows[0].public_ip : aws_instance.tool_windows.public_ip
}

output "tool_windows_private_ip" {
  description = "Windows Tool VM private IP"
  value       = aws_instance.tool_windows.private_ip
}

output "tool_windows_password_data" {
  description = "Windows Tool VM encrypted password data"
  sensitive   = true
  value       = aws_instance.tool_windows.password_data
}

# ROSA Cluster
output "rosa_cluster_id" {
  description = "ROSA cluster ID"
  value       = var.rosa_enabled ? rhcs_cluster_rosa_hcp.rosa_cluster[0].id : ""
}

output "rosa_cluster_name" {
  description = "ROSA cluster name"
  value       = var.rosa_enabled ? rhcs_cluster_rosa_hcp.rosa_cluster[0].name : ""
}

output "rosa_api_url" {
  description = "ROSA cluster API URL"
  value       = var.rosa_enabled ? rhcs_cluster_rosa_hcp.rosa_cluster[0].api_url : ""
}

output "rosa_console_url" {
  description = "ROSA OpenShift Console URL"
  value       = var.rosa_enabled ? rhcs_cluster_rosa_hcp.rosa_cluster[0].console_url : ""
}

output "rosa_admin_password" {
  description = "ROSA cluster-admin password"
  sensitive   = true
  value       = var.rosa_enabled ? random_password.admin_password[0].result : ""
}

output "rosa_login_command" {
  description = "oc login command for cluster access"
  value       = var.rosa_enabled ? "oc login ${rhcs_cluster_rosa_hcp.rosa_cluster[0].api_url} --username cluster-admin --password <run: terraform output -raw rosa_admin_password>" : ""
}

# All Instance IDs (for stop/start scripts)
output "all_instance_ids" {
  description = "All EC2 instance IDs in this lab"
  value = concat(
    [aws_instance.clms.id, aws_instance.kvo.id, aws_instance.tapped_windows.id, aws_instance.tool.id, aws_instance.tool_windows.id],
    var.ubuntu_workload_enabled ? [aws_instance.tapped_ubuntu_1[0].id] : [],
    var.vpb_enabled ? [aws_instance.vpb[0].id] : [],
    var.rhel_enabled ? [aws_instance.tapped_rhel[0].id] : []
  )
}

output "vpb_instance_id" {
  description = "vPB instance ID"
  value       = var.vpb_enabled ? aws_instance.vpb[0].id : "vPB not deployed"
}

# SSH Commands
output "ssh_commands" {
  description = "SSH commands for all VMs"
  value = {
    clms         = "ssh -i ${var.private_key_path} admin@${var.use_elastic_ips ? aws_eip.clms[0].public_ip : aws_instance.clms.public_ip}"
    kvo          = "ssh -i ${var.private_key_path} admin@${var.use_elastic_ips ? aws_eip.kvo[0].public_ip : aws_instance.kvo.public_ip}"
    vpb          = var.vpb_enabled ? "ssh -i ${var.private_key_path} admin@${aws_eip.vpb[0].public_ip}" : "vPB not deployed"
    ubuntu       = var.ubuntu_workload_enabled ? "ssh -i ${var.private_key_path} ubuntu@${var.use_elastic_ips && length(aws_eip.tapped_ubuntu_1) > 0 ? aws_eip.tapped_ubuntu_1[0].public_ip : aws_instance.tapped_ubuntu_1[0].public_ip}" : "Ubuntu not deployed"
    tool_linux   = "ssh -i ${var.private_key_path} ubuntu@${var.use_elastic_ips ? aws_eip.tool[0].public_ip : aws_instance.tool.public_ip}"
    windows      = "RDP to ${var.use_elastic_ips ? aws_eip.tapped_windows[0].public_ip : aws_instance.tapped_windows.public_ip}:3389"
    tool_windows = "RDP to ${var.use_elastic_ips ? aws_eip.tool_windows[0].public_ip : aws_instance.tool_windows.public_ip}:3389"
  }
}

output "credentials" {
  description = "Default credentials for all products"
  sensitive   = true
  value = {
    clms    = { user = "admin", pass = "<CLMS_PASSWORD>" }
    kvo     = { user = "admin", pass = "admin" }
    vpb     = { user = "admin", pass = "<VPB_PASSWORD>" }
    rosa    = { user = "cluster-admin", pass = "run: terraform output -raw rosa_admin_password" }
    ubuntu  = { user = "ubuntu", pass = "Use SSH key" }
    windows = { user = "Administrator", pass = "Decrypt from terraform output" }
  }
}
