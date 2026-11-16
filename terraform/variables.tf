variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Prefix used in resource names (lowercase letters, digits, hyphens)."
  type        = string
  default     = "devops-final"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name must be 3-30 chars: lowercase letters, digits and hyphens only (it is part of the S3 bucket name)."
  }
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block of the public subnet (both servers live here)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type. Use a Free Tier eligible type (t3.micro, or t2.micro in older regions)."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 8
}

variable "ssh_public_key" {
  description = "Content of the SSH PUBLIC key that is allowed to log in. Passed by deploy.sh via TF_VAR_ssh_public_key (never committed)."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to reach SSH (port 22), e.g. 203.0.113.7/32. Passed by deploy.sh (auto-detected public IP)."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr must be a valid CIDR, e.g. 203.0.113.7/32."
  }
}

variable "backup_retention_days" {
  description = "Days after which backups in S3 are deleted automatically."
  type        = number
  default     = 30
}
