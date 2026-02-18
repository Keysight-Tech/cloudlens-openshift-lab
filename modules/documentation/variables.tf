# ============================================================================
# DOCUMENTATION MODULE VARIABLES (OpenShift edition)
# ============================================================================

variable "deployment_prefix" {
  description = "Deployment prefix"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
}

variable "private_key_path" {
  description = "Path to SSH private key"
  type        = string
}

# Keysight Products
variable "clms_public_ip" {
  description = "CLMS public IP"
  type        = string
  default     = ""
}

variable "clms_private_ip" {
  description = "CLMS private IP"
  type        = string
  default     = ""
}

variable "kvo_public_ip" {
  description = "KVO public IP"
  type        = string
  default     = ""
}

variable "vpb_enabled" {
  description = "Whether vPB is deployed"
  type        = bool
  default     = false
}

variable "vpb_public_ip" {
  description = "vPB public IP"
  type        = string
  default     = ""
}

variable "vpb_interfaces" {
  description = "vPB interface IPs"
  type        = map(string)
  default     = {}
}

# Workload VMs
variable "ubuntu_public_ip" {
  description = "Ubuntu VM public IP"
  type        = string
  default     = ""
}

variable "windows_public_ip" {
  description = "Windows VM public IP"
  type        = string
  default     = ""
}

# Tool VMs
variable "tool_linux_public_ip" {
  description = "Linux tool VM public IP"
  type        = string
  default     = ""
}

variable "tool_linux_private_ip" {
  description = "Linux tool VM private IP"
  type        = string
  default     = ""
}

variable "tool_windows_public_ip" {
  description = "Windows tool VM public IP"
  type        = string
  default     = ""
}

variable "tool_windows_private_ip" {
  description = "Windows tool VM private IP"
  type        = string
  default     = ""
}

# ROSA
variable "rosa_enabled" {
  description = "Whether ROSA is deployed"
  type        = bool
  default     = false
}

variable "rosa_cluster_name" {
  description = "ROSA cluster name"
  type        = string
  default     = ""
}

variable "rosa_console_url" {
  description = "OpenShift Console URL"
  type        = string
  default     = ""
}

variable "rosa_api_url" {
  description = "OpenShift API URL"
  type        = string
  default     = ""
}

variable "rosa_login_command" {
  description = "oc login command"
  type        = string
  default     = ""
}

# CyPerf
variable "cyperf_enabled" {
  description = "Whether CyPerf is deployed"
  type        = bool
  default     = false
}

variable "cyperf_controller_public_ip" {
  description = "CyPerf controller public IP"
  type        = string
  default     = ""
}

variable "cyperf_controller_private_ip" {
  description = "CyPerf controller private IP"
  type        = string
  default     = ""
}

variable "output_directory" {
  description = "Directory to write generated files"
  type        = string
}
