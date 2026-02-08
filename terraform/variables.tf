variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-southeast-2" # Sydney — AU/NZ preference
}

variable "environment" {
  description = "Environment name (demo, staging, prod)"
  type        = string
  default     = "demo"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "baseline-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_azs" {
  description = "Availability zones for VPC subnets"
  type        = list(string)
  default     = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes in EKS node group"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes in EKS node group"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes in EKS node group"
  type        = number
  default     = 4
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access EKS public endpoint (restrict to your IP)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Change this to your IP before deploying to production
}

variable "enable_cluster_encryption" {
  description = "Enable envelope encryption for Kubernetes secrets using KMS"
  type        = bool
  default     = true
}
