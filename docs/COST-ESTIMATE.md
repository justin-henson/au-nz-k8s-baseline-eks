# Cost Estimate

This document provides a monthly cost breakdown for the EKS baseline cluster. All prices are in USD and based on AWS Sydney (ap-southeast-2) pricing as of January 2025.

---

## Monthly Cost Breakdown

| Service | Configuration | Monthly Cost |
|---------|---------------|--------------|
| **EKS Control Plane** | 1 cluster | **$73.00** |
| **EC2 Instances** | 2x t3.medium (on-demand) | **$60.40** |
| **EBS Volumes** | 2x 50 GiB gp3 | **$8.00** |
| **NAT Gateway** | 1x NAT Gateway (data transfer: 100 GB) | **$37.85** |
| **Application Load Balancer** | 1x ALB + processing | **$20.00** |
| **Data Transfer** | Outbound to internet (50 GB) | **$4.50** |
| **CloudWatch Logs** | Control plane logs (~5 GB) | **$2.50** |
| **KMS** | 1 key, ~1000 requests/month | **$1.10** |
| **Elastic IP** | 1 EIP for NAT Gateway | **$0.00** (in use) |
| | **TOTAL (baseline)** | **~$207/month** |

---

## Detailed Cost Analysis

### 1. EKS Control Plane
- **Price:** $0.10 per hour
- **Monthly:** $0.10 × 24 × 30 = **$73.00**
- **Notes:**
  - Fixed cost per cluster (regardless of workload size)
  - Covers HA control plane across 3 AZs
  - Includes control plane patching and upgrades

### 2. EC2 Instances (Worker Nodes)
- **Instance Type:** t3.medium (2 vCPU, 4 GiB RAM)
- **Price:** $0.0504 per hour (Sydney region)
- **Configuration:** 2 nodes (min), 4 nodes (max via autoscaling)
- **Monthly (2 nodes):** 2 × $0.0504 × 24 × 30 = **$60.40**
- **Monthly (4 nodes max):** 4 × $0.0504 × 24 × 30 = **$120.80**
- **Notes:**
  - Cluster Autoscaler scales down to 1 node when idle (saves 50%)
  - On-demand pricing (no commitment)
  - Alternative: Spot instances (60-90% discount, but less reliable)

### 3. EBS Volumes
- **Volume Type:** gp3 (general purpose SSD)
- **Size:** 50 GiB per node
- **Price:** $0.08 per GiB-month
- **Configuration:** 2 nodes × 50 GiB
- **Monthly:** 100 GiB × $0.08 = **$8.00**
- **Notes:**
  - Includes baseline 3000 IOPS and 125 MiB/s throughput
  - Additional IOPS/throughput costs extra
  - Volumes encrypted at rest

### 4. NAT Gateway
- **Price:** $0.059 per hour + $0.059 per GB processed
- **Configuration:** 1 NAT Gateway (demo), 3 for production HA
- **Monthly (NAT Gateway):** $0.059 × 24 × 30 = **$42.48**
- **Monthly (Data Processing, 100 GB):** 100 × $0.059 = **$5.90**
- **Total:** $42.48 + $5.90 = **$48.38**
- **Notes:**
  - Largest cost after EKS control plane
  - Single NAT is a single point of failure (prod should use 3)
  - Alternative: VPC endpoints for AWS services (reduces data transfer)

**Production (3 NAT Gateways):** $42.48 × 3 + $5.90 = **$133.34/month**

### 5. Application Load Balancer (ALB)
- **Price:** $0.0243 per hour + LCU charges
- **Monthly (ALB):** $0.0243 × 24 × 30 = **$17.50**
- **Monthly (LCU processing):** Estimated **$2.50** (low traffic demo)
- **Total:** **$20.00**
- **Notes:**
  - LCU charges based on: new connections, active connections, bytes processed, rule evaluations
  - Low traffic demo: ~0.1-0.2 LCU-hours/hour
  - Production with high traffic: can be $50-100+/month

### 6. Data Transfer
- **Outbound to Internet:** $0.09 per GB (first 10 TB/month)
- **Monthly (50 GB):** 50 × $0.09 = **$4.50**
- **Notes:**
  - Inbound data transfer is free
  - Inter-AZ data transfer: $0.01 per GB (minimal for this demo)
  - VPC endpoints can reduce data transfer costs for AWS services

### 7. CloudWatch Logs
- **Ingestion:** $0.50 per GB
- **Storage:** $0.03 per GB-month (after 5 GB free tier)
- **Monthly (control plane logs, ~5 GB ingested):** 5 × $0.50 = **$2.50**
- **Notes:**
  - Control plane logs are relatively small
  - Container logs (if enabled with Fluent Bit) add significantly more cost
  - Consider log retention policies (default: never expire)

### 8. KMS (Key Management Service)
- **Key:** $1.00 per month per key
- **Requests:** $0.03 per 10,000 requests
- **Monthly:** $1.00 + (1000 ÷ 10,000 × $0.03) = **$1.10**
- **Notes:**
  - Used for envelope encryption of Kubernetes secrets
  - Minimal request cost for demo workload

---

## Cost Optimization Strategies

### Immediate (Demo-Friendly)
1. **Cluster Autoscaler:** Scale down to 1 node when idle → **Save $30/month**
2. **Scheduled Scaling:** Stop cluster outside business hours (16h/day) → **Save ~40%**
3. **Tear Down When Not Using:** Use `./scripts/teardown.sh` → **Save 100%**

### Production Optimizations
1. **Reserved Instances:** 1-year commitment → **Save ~30% on EC2**
2. **Savings Plans:** Flexible 1-year commitment → **Save ~20-30% on EC2**
3. **Spot Instances:** For non-critical workloads → **Save 60-90% on EC2**
4. **Fargate:** For intermittent workloads (no idle node cost) → **Variable savings**
5. **VPC Endpoints:** For S3, DynamoDB, etc. → **Reduce data transfer costs**
6. **EBS gp2 → gp3:** (already using gp3) → **Save ~20% vs gp2**
7. **Karpenter:** Better bin-packing → **Reduce wasted capacity**

### Monthly Cost Scenarios

| Scenario | Configuration | Monthly Cost |
|----------|---------------|--------------|
| **Demo (Minimal)** | 1 node, single NAT, low traffic | **$155** |
| **Demo (Baseline)** | 2 nodes, single NAT, ALB | **$207** |
| **Demo (Peak)** | 4 nodes autoscaled | **$267** |
| **Production (HA)** | 3 nodes, 3 NAT gateways, HA ALB | **$350+** |
| **Production (Spot)** | 3 Spot nodes, 3 NAT gateways | **$270+** |
| **Production (RI)** | 3 reserved nodes, 3 NAT gateways | **$280+** |

---

## Hourly Cost Breakdown (For Testing)

| Duration | Estimated Cost |
|----------|----------------|
| 1 hour | **$0.29** |
| 8 hours | **$2.30** |
| 1 day | **$6.90** |
| 1 week | **$48.30** |

**Tip:** For portfolio review purposes, deploy for a few hours, take screenshots, then tear down to minimize cost.

---

## Free Tier Eligibility

AWS Free Tier includes:
- ❌ **EKS Control Plane:** Not covered (always $73/month)
- ✅ **EC2 (first 12 months):** 750 hours/month of t2.micro or t3.micro
  - **Note:** This demo uses t3.medium (not covered)
- ✅ **EBS (first 12 months):** 30 GiB of gp2 or gp3 storage
  - **This demo:** Uses 100 GiB (70 GiB billable)
- ✅ **CloudWatch Logs:** First 5 GB ingestion free
- ✅ **Data Transfer:** First 100 GB/month outbound free (for 12 months)

**Result:** If using t3.micro nodes (1 vCPU, 2 GiB RAM), you could save ~$30/month on EC2 during first year, but t3.micro is too small for realistic workloads.

---

## Cost Comparison: EKS vs Alternatives

| Platform | Monthly Cost (2 nodes) | Notes |
|----------|------------------------|-------|
| **EKS (this demo)** | **$207** | Managed control plane, production-ready |
| **ECS + Fargate** | **$50-100** | Serverless containers, simpler than K8s |
| **Self-managed K8s** | **$60** | No control plane fee, but manual maintenance |
| **GKE (Google)** | **$146** | $0.10/hr control plane, similar pricing |
| **AKS (Azure)** | **$60** | Free control plane, but node costs similar |

---

## Billing Alerts (Recommended)

Set up AWS Budgets to avoid surprise costs:

```bash
# Create a budget alert for $50/month
aws budgets create-budget \
  --account-id YOUR_ACCOUNT_ID \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json
```

**Recommended Alerts:**
- Budget: $300/month (production)
- Budget: $100/month (demo)
- Anomaly detection: 20% increase over baseline

---

## Summary

**Monthly cost for this baseline demo:** **~$207 USD**

**Key cost drivers:**
1. EKS control plane: $73 (35%)
2. EC2 nodes: $60 (29%)
3. NAT Gateway: $48 (23%)
4. ALB: $20 (10%)
5. Other: $6 (3%)

**For reviewers:**
- Deploy for a few hours for testing (~$2-5 total cost)
- Use `./scripts/teardown.sh` to clean up all resources
- Monitor AWS Billing dashboard during deployment

**For production:**
- Budget ~$350-500/month for HA configuration
- Use Spot/RI for cost savings
- Implement VPC endpoints to reduce data transfer
- Monitor and right-size node instances
