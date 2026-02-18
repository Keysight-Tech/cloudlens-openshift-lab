# ============================================================================
# ROSA-LAB MODULE VARIABLES
# ============================================================================

# Identity
variable "deployment_prefix" {
  description = "Unique prefix for this lab environment"
  type        = string
}

variable "lab_index" {
  description = "Numeric index of this lab (1-25)"
  type        = number
}

variable "owner" {
  description = "Owner name for this lab"
  type        = string
}

# AWS Configuration
variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
}

variable "availability_zone" {
  description = "Primary availability zone"
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "private_key_path" {
  description = "Path to SSH private key"
  type        = string
}

# Network CIDRs
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "management_subnet_cidr" {
  description = "CIDR for management subnet"
  type        = string
}

variable "ingress_subnet_cidr" {
  description = "CIDR for vPB ingress subnet"
  type        = string
}

variable "egress_subnet_cidr" {
  description = "CIDR for vPB egress subnet"
  type        = string
}

variable "rosa_public_subnet_az1_cidr" {
  description = "CIDR for ROSA public subnet AZ1"
  type        = string
}

variable "rosa_private_subnet_az1_cidr" {
  description = "CIDR for ROSA private subnet AZ1"
  type        = string
}

variable "rosa_public_subnet_az2_cidr" {
  description = "CIDR for ROSA public subnet AZ2"
  type        = string
}

variable "rosa_private_subnet_az2_cidr" {
  description = "CIDR for ROSA private subnet AZ2"
  type        = string
}

# Security
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_https_cidr" {
  description = "CIDR block allowed for HTTPS access"
  type        = string
  default     = "0.0.0.0/0"
}

# Features
variable "rosa_enabled" {
  description = "Enable ROSA cluster for this lab"
  type        = bool
  default     = true
}

variable "vpb_enabled" {
  description = "Enable vPB deployment (requires AWS Marketplace subscription)"
  type        = bool
  default     = true
}

variable "ubuntu_workload_enabled" {
  description = "Enable Ubuntu workload VM"
  type        = bool
  default     = true
}

variable "rhel_enabled" {
  description = "Enable RHEL VM deployment"
  type        = bool
  default     = false
}

# Instance Types
variable "clms_instance_type" {
  description = "Instance type for CLMS"
  type        = string
  default     = "t3.xlarge"
}

variable "kvo_instance_type" {
  description = "Instance type for KVO"
  type        = string
  default     = "t3.2xlarge"
}

variable "vpb_instance_type" {
  description = "Instance type for vPB"
  type        = string
  default     = "t3.xlarge"
}

variable "ubuntu_instance_type" {
  description = "Instance type for Ubuntu VMs"
  type        = string
  default     = "t3.medium"
}

variable "windows_instance_type" {
  description = "Instance type for Windows VMs"
  type        = string
  default     = "t3.medium"
}

variable "rhel_instance_type" {
  description = "Instance type for RHEL VM"
  type        = string
  default     = "t3.medium"
}

variable "tool_linux_instance_type" {
  description = "Instance type for Linux tool VM"
  type        = string
  default     = "t3.medium"
}

variable "tool_windows_instance_type" {
  description = "Instance type for Windows tool VM"
  type        = string
  default     = "t3.large"
}

# ROSA Configuration
variable "openshift_version" {
  description = "OpenShift version (e.g. '4.15'). Empty = latest stable."
  type        = string
  default     = ""
}

variable "rosa_node_instance_type" {
  description = "EC2 instance type for ROSA worker nodes"
  type        = string
  default     = "m5.xlarge"
}

variable "rosa_node_count" {
  description = "Number of ROSA worker nodes"
  type        = number
  default     = 2
}

variable "rosa_node_min_count" {
  description = "Minimum ROSA worker nodes"
  type        = number
  default     = 2
}

variable "rosa_node_max_count" {
  description = "Maximum ROSA worker nodes"
  type        = number
  default     = 4
}

# Elastic IPs
variable "use_elastic_ips" {
  description = "Use Elastic IPs for static public IPs"
  type        = bool
  default     = true
}

# Tags
variable "extra_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
