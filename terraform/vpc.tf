module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.16"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.vpc_azs
  private_subnets = [for k, v in var.vpc_azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in var.vpc_azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # Cost optimization for demo; prod should use one per AZ
  enable_dns_hostnames = true
  enable_dns_support   = true

  # EKS requires these tags for subnet discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    # Allow EKS to discover subnets for public load balancers
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    # Allow EKS to discover subnets for internal load balancers
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}
