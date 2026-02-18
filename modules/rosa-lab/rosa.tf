# ============================================================================
# ROSA HCP CLUSTER (Red Hat OpenShift Service on AWS - Hosted Control Planes)
# ============================================================================
#
# Architecture:
#   - ROSA HCP: Control plane hosted by Red Hat (no control plane EC2 costs)
#   - Worker nodes: Run in customer VPC private subnets
#   - Networking: OVN-Kubernetes CNI (replaces VPC CNI used by EKS)
#   - Auth: STS (short-lived tokens) - no long-lived IAM keys in cluster
#
# Prerequisites:
#   1. Red Hat account with ROSA enabled
#   2. rosa CLI installed: https://console.redhat.com/openshift/downloads
#   3. OCM token in terraform.tfvars (rhcs_token)
#   4. Run once per AWS account: rosa create account-roles --hosted-cp --mode auto
#
# IMPORTANT: ROSA account roles must exist BEFORE terraform apply.
# The null_resource below creates them if they don't exist.
# ============================================================================

# ============================================================================
# ROSA ACCOUNT ROLES (once per AWS account)
# Creates: Installer, Support, Worker roles for ROSA HCP
# ============================================================================

resource "null_resource" "rosa_account_roles" {
  count = var.rosa_enabled ? 1 : 0

  triggers = {
    deployment_prefix = var.deployment_prefix
    aws_region        = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Creating ROSA HCP account roles (idempotent - safe to re-run)..."
      rosa create account-roles \
        --mode auto \
        --prefix "${var.deployment_prefix}" \
        --hosted-cp \
        --yes \
        --region "${var.aws_region}" 2>&1 | tee /tmp/rosa-account-roles.log
      echo "Account roles created or already exist."
    EOT
  }
}

# ============================================================================
# OIDC CONFIGURATION (per cluster)
# ============================================================================

resource "rhcs_rosa_oidc_config" "oidc_config" {
  count   = var.rosa_enabled ? 1 : 0
  managed = true

  depends_on = [null_resource.rosa_account_roles]
}

# ============================================================================
# ROSA HCP CLUSTER
# ============================================================================

data "rhcs_versions" "all" {}

locals {
  # Use specified version or pick latest stable
  openshift_version = var.openshift_version != "" ? var.openshift_version : (
    length([for v in data.rhcs_versions.all.items : v.raw_id
      if v.rosa_enabled && !v.end_of_life_timestamp != ""]) > 0
    ? sort([for v in data.rhcs_versions.all.items : v.raw_id
        if v.rosa_enabled])[length(sort([for v in data.rhcs_versions.all.items : v.raw_id
      if v.rosa_enabled])) - 1]
    : "4.15"
  )

  account_role_prefix = var.deployment_prefix
}

resource "rhcs_cluster_rosa_hcp" "rosa_cluster" {
  count = var.rosa_enabled ? 1 : 0

  name             = local.rosa_cluster_name
  cloud_region     = var.aws_region
  aws_account_id   = data.aws_caller_identity.current.account_id
  aws_billing_account_id = data.aws_caller_identity.current.account_id

  # Network - workers run in private subnets
  aws_subnet_ids = [
    aws_subnet.rosa_private_az1[0].id,
    aws_subnet.rosa_private_az2[0].id,
    aws_subnet.rosa_public_az1[0].id,
    aws_subnet.rosa_public_az2[0].id,
  ]

  # Pod and service CIDRs (must not overlap with VPC CIDR 10.1.0.0/16)
  machine_cidr    = var.vpc_cidr
  service_cidr    = "172.30.0.0/16"
  pod_cidr        = "10.128.0.0/14"
  host_prefix     = 23

  # STS authentication - uses OIDC for short-lived tokens
  sts = {
    oidc_config_id       = rhcs_rosa_oidc_config.oidc_config[0].id
    operator_role_prefix = var.deployment_prefix
    role_arn             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.account_role_prefix}-HCP-ROSA-Installer-Role"
    support_role_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.account_role_prefix}-HCP-ROSA-Support-Role"
    instance_iam_roles = {
      worker_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.account_role_prefix}-HCP-ROSA-Worker-Role"
    }
  }

  version                = local.openshift_version
  multi_az               = true
  private                = false   # Public API endpoint (accessible from internet)

  tags = {
    Deployment = var.deployment_prefix
    Owner      = var.owner
    ManagedBy  = "Terraform"
  }

  depends_on = [
    null_resource.rosa_account_roles,
    rhcs_rosa_oidc_config.oidc_config,
    aws_nat_gateway.rosa_az1,
    aws_nat_gateway.rosa_az2,
  ]
}

# ============================================================================
# ROSA OPERATOR ROLES (per cluster, created after cluster resource)
# ============================================================================

resource "null_resource" "rosa_operator_roles" {
  count = var.rosa_enabled ? 1 : 0

  triggers = {
    cluster_id = var.rosa_enabled ? rhcs_cluster_rosa_hcp.rosa_cluster[0].id : ""
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Creating ROSA operator roles for cluster ${rhcs_cluster_rosa_hcp.rosa_cluster[0].id}..."
      rosa create operator-roles \
        --mode auto \
        --cluster "${rhcs_cluster_rosa_hcp.rosa_cluster[0].id}" \
        --yes \
        --region "${var.aws_region}" 2>&1
      echo "Operator roles created."
    EOT
  }

  depends_on = [rhcs_cluster_rosa_hcp.rosa_cluster]
}

# ============================================================================
# ROSA MACHINE POOL (worker nodes)
# ============================================================================

resource "rhcs_machine_pool" "worker_pool" {
  count = var.rosa_enabled ? 1 : 0

  cluster      = rhcs_cluster_rosa_hcp.rosa_cluster[0].id
  name         = "worker"
  machine_type = var.rosa_node_instance_type
  replicas     = var.rosa_node_count

  autoscaling_enabled = true
  min_replicas        = var.rosa_node_min_count
  max_replicas        = var.rosa_node_max_count

  labels = {
    role        = "worker"
    environment = var.deployment_prefix
    owner       = local.owner_sanitized
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.rosa_cluster,
    null_resource.rosa_operator_roles,
  ]
}

# ============================================================================
# ROSA CLUSTER ADMIN USER
# Creates an htpasswd identity provider with a cluster-admin user
# ============================================================================

resource "rhcs_identity_provider" "htpasswd" {
  count      = var.rosa_enabled ? 1 : 0
  cluster    = rhcs_cluster_rosa_hcp.rosa_cluster[0].id
  name       = "cluster-admin-idp"
  mapping_method = "claim"

  htpasswd = {
    users = [{
      username = "cluster-admin"
      password = random_password.admin_password[0].result
    }]
  }

  depends_on = [rhcs_cluster_rosa_hcp.rosa_cluster]
}

resource "random_password" "admin_password" {
  count   = var.rosa_enabled ? 1 : 0
  length  = 16
  special = true
  # Must meet OpenShift password policy
  override_special = "!@#%^&*"
}

resource "rhcs_group_membership" "cluster_admin" {
  count   = var.rosa_enabled ? 1 : 0
  cluster = rhcs_cluster_rosa_hcp.rosa_cluster[0].id
  group   = "cluster-admins"
  user    = "cluster-admin"

  depends_on = [rhcs_identity_provider.htpasswd]
}
