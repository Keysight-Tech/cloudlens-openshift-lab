# ============================================================================
# CLOUDLENS OPENSHIFT VISIBILITY LAB
# ============================================================================
# Deploys a single lab environment with:
#   - CloudLens Manager (CLMS)
#   - Keysight Vision One (KVO)
#   - Virtual Packet Broker (vPB)
#   - Ubuntu and Windows workload VMs
#   - Linux and Windows tool VMs
#   - ROSA HCP cluster (Red Hat OpenShift on AWS)
#   - Optional CyPerf Controller
# ============================================================================

module "lab" {
  source = "../modules/rosa-lab"

  # Identity
  deployment_prefix = var.deployment_prefix
  lab_index         = 1
  owner             = var.deployment_prefix

  # AWS Configuration
  aws_region       = var.aws_region
  aws_profile      = var.aws_profile
  key_pair_name    = var.key_pair_name
  private_key_path = var.private_key_path

  # Network CIDRs
  vpc_cidr                     = var.vpc_cidr
  management_subnet_cidr       = var.management_subnet_cidr
  ingress_subnet_cidr          = var.ingress_subnet_cidr
  egress_subnet_cidr           = var.egress_subnet_cidr
  rosa_public_subnet_az1_cidr  = var.rosa_public_subnet_az1_cidr
  rosa_private_subnet_az1_cidr = var.rosa_private_subnet_az1_cidr
  rosa_public_subnet_az2_cidr  = var.rosa_public_subnet_az2_cidr
  rosa_private_subnet_az2_cidr = var.rosa_private_subnet_az2_cidr

  # Security
  allowed_ssh_cidr   = var.allowed_ssh_cidr
  allowed_https_cidr = var.allowed_https_cidr

  # Features
  rosa_enabled            = var.rosa_enabled
  vpb_enabled             = var.vpb_enabled
  use_elastic_ips         = var.use_elastic_ips
  ubuntu_workload_enabled = true
  rhel_enabled            = false

  # Instance Types
  clms_instance_type         = var.clms_instance_type
  kvo_instance_type          = var.kvo_instance_type
  vpb_instance_type          = var.vpb_instance_type
  ubuntu_instance_type       = var.ubuntu_instance_type
  windows_instance_type      = var.windows_instance_type
  tool_linux_instance_type   = var.ubuntu_instance_type
  tool_windows_instance_type = "t3.large"

  # ROSA
  openshift_version     = var.openshift_version
  rosa_node_instance_type = var.rosa_node_instance_type
  rosa_node_count       = var.rosa_node_count
  rosa_node_min_count   = var.rosa_node_min_count
  rosa_node_max_count   = var.rosa_node_max_count

  # Tags
  extra_tags = var.extra_tags
}

# ============================================================================
# DOCUMENTATION GENERATOR
# ============================================================================

module "documentation" {
  source = "../modules/documentation"

  deployment_prefix = var.deployment_prefix
  aws_region        = var.aws_region
  aws_profile       = var.aws_profile
  private_key_path  = var.private_key_path

  # Keysight Products
  clms_public_ip  = module.lab.clms_public_ip
  clms_private_ip = module.lab.clms_private_ip
  kvo_public_ip   = module.lab.kvo_public_ip
  vpb_enabled     = var.vpb_enabled
  vpb_public_ip   = module.lab.vpb_public_ip
  vpb_interfaces  = module.lab.vpb_interfaces

  # Workload VMs
  ubuntu_public_ip  = module.lab.ubuntu_1_public_ip
  windows_public_ip = module.lab.windows_public_ip

  # Tool VMs
  tool_linux_public_ip    = module.lab.tool_linux_public_ip
  tool_linux_private_ip   = module.lab.tool_linux_private_ip
  tool_windows_public_ip  = module.lab.tool_windows_public_ip
  tool_windows_private_ip = module.lab.tool_windows_private_ip

  # ROSA
  rosa_enabled      = var.rosa_enabled
  rosa_cluster_name = module.lab.rosa_cluster_name
  rosa_console_url  = module.lab.rosa_console_url
  rosa_api_url      = module.lab.rosa_api_url
  rosa_login_command = module.lab.rosa_login_command

  # CyPerf
  cyperf_enabled               = var.cyperf_enabled
  cyperf_controller_public_ip  = var.cyperf_enabled ? aws_eip.cyperf_controller[0].public_ip : ""
  cyperf_controller_private_ip = var.cyperf_enabled ? aws_instance.cyperf_controller[0].private_ip : ""

  output_directory = "${path.module}/generated/${var.deployment_prefix}"

  depends_on = [module.lab]
}
