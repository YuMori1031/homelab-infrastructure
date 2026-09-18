variable "aws_region" {
  description = "AWS region containing the HomeLab VPC."
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile used by Terraform. Credentials are not stored in this repository."
  type        = string
  default     = "homelab-codex"
}

variable "availability_zone" {
  description = "Availability Zone for the monitoring subnet."
  type        = string
  default     = "ap-northeast-1a"
}

variable "vpc_name" {
  description = "Name tag of the existing HomeLab VPC."
  type        = string
  default     = "home-lab-vpc"
}

variable "vpc_cidr" {
  description = "Expected CIDR of the existing HomeLab VPC."
  type        = string
  default     = "10.10.0.0/24"
}

variable "monitoring_subnet_cidr" {
  description = "CIDR allocated to the Zabbix monitoring subnet."
  type        = string
  default     = "10.10.0.240/28"
}

variable "zabbix_private_ip" {
  description = "Fixed private IPv4 address for the Zabbix EC2 instance."
  type        = string
  default     = "10.10.0.254"
}

variable "zabbix_ami_id" {
  description = "Pinned Debian 13 ARM64 AMI ID for the existing Zabbix EC2 instance. Supply from environment-specific tfvars; changing it can replace the instance."
  type        = string
}

variable "zabbix_instance_type" {
  description = "ARM64 burstable instance type for the Zabbix server."
  type        = string
  default     = "t4g.small"

  validation {
    condition     = var.zabbix_instance_type == "t4g.small"
    error_message = "Phase 0 is intentionally pinned to t4g.small for the 2026 Free Trial."
  }
}

variable "zabbix_root_volume_size" {
  description = "Size in GiB of the encrypted gp3 root volume."
  type        = number
  default     = 30

  validation {
    condition     = var.zabbix_root_volume_size == 30
    error_message = "The approved Phase 0 root volume size is 30 GiB."
  }
}

variable "enable_zabbix_trapper_ingress" {
  description = "Enable TCP/10051 from HomeLab networks for active agents or trapper traffic after the monitoring design is approved."
  type        = bool
  default     = false
}

variable "vpn_eni_id" {
  description = "Current production VPN ENI in the 10.10.0.0/28 subnet, used as the route target."
  type        = string
}

variable "vpn_private_ip" {
  description = "Expected private IPv4 address on the current production VPN ENI."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to resources managed by this Terraform configuration."
  type        = map(string)
  default = {
    Environment = "HomeLab"
    ManagedBy   = "Terraform"
    Project     = "Zabbix"
  }
}
