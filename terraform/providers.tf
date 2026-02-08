provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "au-nz-k8s-baseline-eks"
      ManagedBy   = "terraform"
      Environment = var.environment
      Owner       = "justin-henson"
    }
  }
}
