# EKS Baseline Terraform Root Module
# This module provisions a production-ready EKS cluster with:
# - VPC with public/private subnets across 3 AZs
# - EKS cluster with managed node group
# - IRSA (IAM Roles for Service Accounts) setup
# - Essential EKS add-ons (CoreDNS, kube-proxy, VPC CNI, EBS CSI)
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
#
# After deployment, configure kubectl:
#   aws eks update-kubeconfig --region ap-southeast-2 --name baseline-eks

# The actual resources are defined in separate files for better organization:
# - vpc.tf: VPC and networking
# - eks.tf: EKS cluster and node groups
# - iam.tf: IAM roles for IRSA
# - addons.tf: EKS managed add-ons
