module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.2"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Network configuration
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Cluster endpoint access: public + private for flexibility in demo
  # In production, consider private-only with VPN/bastion access
  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.allowed_cidr_blocks

  # Enable IRSA (IAM Roles for Service Accounts)
  # This is the modern, secure way to grant AWS permissions to pods
  enable_irsa = true

  # Cluster encryption
  # Disabled to work around KMS type mismatch bug in EKS module
  create_kms_key              = false
  cluster_encryption_config   = {}

  # Cluster logging
  # Enable control plane logs for audit and troubleshooting
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Cluster access configuration
  # Grant cluster admin access to the Terraform executor
  enable_cluster_creator_admin_permissions = true

  # Managed node group
  eks_managed_node_groups = {
    default = {
      name = "nodes"

      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND" # Use ON_DEMAND for reliability; SPOT for cost savings

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Node labels for workload targeting
      labels = {
        Environment = var.environment
        NodeGroup   = "default"
      }

      # Taints can be used to dedicate nodes to specific workloads
      # Uncomment if you need dedicated nodes
      # taints = [
      #   {
      #     key    = "dedicated"
      #     value  = "default"
      #     effect = "NoSchedule"
      #   }
      # ]

      # Node group IAM role will have these policies attached automatically
      # Additional policies can be attached via iam_role_additional_policies

      # Block device configuration
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50 # GB — adjust based on workload needs
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 125
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Metadata options for IMDSv2 (security best practice)
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required" # Enforce IMDSv2
        http_put_response_hop_limit = 1
        instance_metadata_tags      = "disabled"
      }

      tags = {
        # Enable Cluster Autoscaler to discover this node group
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
        "k8s.io/cluster-autoscaler/enabled"             = "true"
      }
    }
  }

  tags = {
    Name = var.cluster_name
  }
}
