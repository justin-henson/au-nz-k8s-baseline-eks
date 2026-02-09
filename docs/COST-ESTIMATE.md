# Cost Estimate

Monthly and per-test cost estimates for the EKS baseline cluster in ap-southeast-2 (Sydney).

## Demo / Test Cycle (1-2 Hours)

Use this estimate when spinning up the cluster to validate, then destroying immediately.

| Resource | Rate | 2-Hour Cost |
|----------|------|-------------|
| EKS control plane | $0.10/hr | $0.20 |
| 2x t3.medium nodes | $0.0416/hr each | $0.17 |
| NAT Gateway | $0.045/hr | $0.09 |
| EBS (2x 20GB gp3) | $0.08/GB/month prorated | $0.01 |
| Data transfer | ~minimal for test | $0.01 |
| **Total** | | **~$0.50** |

Deploy takes ~15 minutes, testing ~30 minutes, destroy ~15 minutes. A full test cycle
runs under $1.00.

## Running 24/7 (Monthly)

| Resource | Rate | Monthly Cost |
|----------|------|-------------|
| EKS control plane | $0.10/hr | $73.00 |
| 2x t3.medium nodes | $0.0416/hr each | $60.90 |
| NAT Gateway (1 AZ) | $0.045/hr + data | $32.85 + data |
| EBS (2x 20GB gp3) | $0.08/GB/month | $3.20 |
| CloudWatch logs | ~5GB/month | $3.17 |
| Data transfer (inter-AZ) | $0.01/GB | ~$2.00 |
| **Total** | | **~$175/month** |

## Cost Reduction Options

**For development/testing environments:**

- Use a single NAT Gateway instead of one per AZ (saves ~$65/month)
- Use t3.small nodes instead of t3.medium (saves ~$30/month)
- Schedule cluster downtime outside business hours (saves ~65%)
- Use Spot instances for non-critical workloads (saves 60-90% on compute)

**For production environments:**

- Reserved Instances or Savings Plans for nodes (saves 30-40%)
- Use Karpenter instead of Cluster Autoscaler for better bin-packing
- Right-size pods with VPA recommendations before setting resource limits
- Monitor unused resources with AWS Cost Explorer

## Pricing Notes

- All prices are for ap-southeast-2 (Sydney) as of February 2026
- EKS control plane pricing is the same across all regions
- NAT Gateway data processing adds $0.045/GB on top of the hourly rate
- Inter-AZ data transfer applies when pods communicate across availability zones
- This baseline uses a single NAT Gateway to keep demo costs low

## What This Cluster Includes at These Prices

- Managed Kubernetes control plane (highly available, AWS-managed)
- 2 worker nodes across 2 availability zones
- VPC with public and private subnets in 3 AZs
- CoreDNS, kube-proxy, VPC CNI, EBS CSI driver
- Pod Security Standards enforcing restricted mode
- IRSA for secure pod-level AWS access
