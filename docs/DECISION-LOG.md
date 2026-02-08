# Decision Log

This document records key architectural and implementation decisions made for this EKS baseline, including the rationale and trade-offs considered.

---

## Decision 1: EKS vs Self-Managed Kubernetes vs Fargate

**Decision:** Use Amazon EKS with managed node groups.

**Context:**
- Need production-ready Kubernetes for portfolio demonstration
- Want to show understanding of AWS-native services
- Limited time for cluster maintenance

**Options Considered:**

### A. Amazon EKS (Chosen)
**Pros:**
- Managed control plane (HA, patching, upgrades handled by AWS)
- Integrated with AWS services (IAM, VPC, ALB, EBS)
- Industry standard for AWS environments
- SLA-backed availability

**Cons:**
- Cost: $0.10/hour for control plane (~$73/month)
- Less control over control plane configuration
- AWS vendor lock-in

### B. Self-Managed Kubernetes (kops, kubeadm)
**Pros:**
- Full control over all components
- Lower cost (no control plane fee)
- Portable to other clouds

**Cons:**
- Complex setup and maintenance
- Responsible for control plane HA
- Responsible for security patches
- Time-consuming for a portfolio project

### C. EKS on Fargate
**Pros:**
- Serverless (no node management)
- Pay only for pod runtime
- Automatic scaling

**Cons:**
- More expensive for steady-state workloads
- Limited to certain workloads (no DaemonSets, privileged containers)
- Cold start latency
- Not representative of typical AU/NZ production deployments

**Outcome:**
EKS chosen because:
1. Demonstrates AWS service integration knowledge
2. Matches AU/NZ employer expectations (most job listings specify EKS)
3. Allows focus on application deployment rather than cluster operations
4. Production-ready out of the box

---

## Decision 2: Managed Node Groups vs Self-Managed vs Karpenter

**Decision:** Use EKS Managed Node Groups.

**Context:**
- Need worker nodes for general-purpose workloads
- Want balance between simplicity and control

**Options Considered:**

### A. EKS Managed Node Groups (Chosen)
**Pros:**
- AWS handles AMI updates and node lifecycle
- Automatic integration with EKS control plane
- Simplified rolling updates
- Good balance of control and convenience

**Cons:**
- Less customization than self-managed
- Slightly more expensive than self-managed
- Limited to AWS AMI choices

### B. Self-Managed Node Groups
**Pros:**
- Full control over node configuration
- Can use custom AMIs
- Slightly lower cost

**Cons:**
- Responsible for AMI patching
- Manual integration with cluster autoscaler
- More operational overhead

### C. Karpenter
**Pros:**
- Just-in-time node provisioning (faster scaling)
- Better bin-packing (cost savings)
- No ASG configuration required
- Flexible instance type selection

**Cons:**
- Newer, less mature than ASG-based autoscaling
- Additional learning curve
- More complex to set up initially

**Outcome:**
Managed node groups chosen because:
1. Simpler for portfolio demonstration
2. Standard approach in most organizations
3. AWS handles patching (security benefit)
4. Can migrate to Karpenter later if needed (included note in docs)

---

## Decision 3: IRSA vs Node-Level IAM Roles

**Decision:** Use IAM Roles for Service Accounts (IRSA).

**Context:**
- Pods need AWS API access (e.g., S3, SQS, DynamoDB)
- Security best practice is least privilege

**Options Considered:**

### A. IRSA (Chosen)
**Pros:**
- Pod-level IAM permissions (least privilege)
- No AWS credentials in pods
- Works with OIDC identity federation
- Auditable (CloudTrail shows which pod assumed which role)

**Cons:**
- Requires OIDC provider setup
- Slightly more complex initial configuration
- Each workload needs its own IAM role

### B. Node-Level IAM Roles
**Pros:**
- Simpler setup (one role per node group)
- Easier to understand for beginners

**Cons:**
- All pods on a node share the same permissions (security risk)
- Violates principle of least privilege
- Difficult to audit which pod made which API call
- Not recommended for production

**Outcome:**
IRSA chosen because:
1. Production security best practice
2. Demonstrates understanding of IAM/Kubernetes integration
3. Key interview talking point for AU/NZ DevOps roles
4. Allows showcasing AWS security knowledge

**Implementation:**
- OIDC provider enabled in terraform/eks.tf
- Example IAM role in terraform/iam.tf
- ServiceAccount annotation in k8s/demo-app/deployment.yaml

---

## Decision 4: ALB Ingress Controller vs Nginx Ingress

**Decision:** Use AWS Load Balancer Controller for ALB ingress.

**Context:**
- Need to expose demo app to internet
- Want to show AWS-native approach

**Options Considered:**

### A. AWS Load Balancer Controller (Chosen)
**Pros:**
- AWS-native (provisions ALB/NLB directly)
- Integrated with AWS services (ACM, WAF, Shield)
- No in-cluster load balancer pods needed
- ALB health checks at target level
- Native AWS cost management and monitoring

**Cons:**
- AWS-specific (not portable)
- Requires IRSA setup
- ALB costs ($0.0225/hour + LCU charges)

### B. Nginx Ingress Controller
**Pros:**
- Cloud-agnostic (portable)
- Rich feature set (rate limiting, auth, rewrites)
- Widely used, good community support
- Free (just node/pod resource costs)

**Cons:**
- Requires LoadBalancer Service (provisions NLB/CLB)
- In-cluster pods handle all traffic (scaling concern)
- SSL termination in-cluster (not using ACM)
- Need to manage cert renewals

**Outcome:**
AWS Load Balancer Controller chosen because:
1. Shows AWS service integration (ALB, Target Groups, Security Groups)
2. More common in AU/NZ AWS environments
3. Better AWS ecosystem integration (ACM, WAF, CloudWatch)
4. Portfolio goal is to demonstrate AWS/EKS proficiency

**Note:** For multi-cloud or Kubernetes-first organizations, Nginx would be the better choice.

---

## Decision 5: Network Policy Approach

**Decision:** Implement restrictive network policies with default deny + explicit allow.

**Context:**
- Need to demonstrate Kubernetes security understanding
- Want defense-in-depth approach

**Options Considered:**

### A. Default Deny + Explicit Allow (Chosen)
**Pros:**
- Security best practice (zero trust)
- Forces conscious decisions about traffic flows
- Easier to audit (all allowed traffic is documented)

**Cons:**
- More initial configuration work
- Can break applications if policies are too restrictive
- Requires understanding of all traffic flows

### B. Allow All (Default)
**Pros:**
- Simplest to implement
- No risk of breaking applications

**Cons:**
- No network segmentation
- Lateral movement easy for attackers
- Not production-ready

### C. Namespace-Level Isolation Only
**Pros:**
- Balance between security and simplicity
- Prevents cross-namespace traffic

**Cons:**
- No protection within namespace
- All pods in namespace can talk to each other

**Outcome:**
Default deny + explicit allow chosen because:
1. Demonstrates security-first mindset
2. Common in financial services / regulated industries (AU/NZ)
3. Shows understanding of Kubernetes networking
4. Portfolio piece should show best practices

**Implementation:**
- `default-deny-ingress` policy in each namespace
- Explicit allow rules for ALB → pods, monitoring → pods
- Egress allowed for DNS and external APIs

**Note:** Using Calico or Cilium would provide L7 network policies (HTTP path-based rules), but AWS VPC CNI with built-in network policies is simpler for demos.

---

## Decision 6: Single vs Multi-AZ NAT Gateway

**Decision:** Single NAT Gateway for demo, document multi-AZ for production.

**Context:**
- NAT Gateway costs $0.045/hour ($32/month)
- Portfolio demo should minimize cost

**Options:**

### A. Single NAT Gateway (Chosen for Demo)
**Cost:** ~$32/month + data transfer
**Availability:** Single point of failure

### B. NAT Gateway per AZ (Production)
**Cost:** ~$96/month (3x) + data transfer
**Availability:** High availability

**Outcome:**
Single NAT for demo, with clear documentation that production should use one per AZ.
- Documented in terraform/vpc.tf with comment
- Noted in docs/COST-ESTIMATE.md
- Trade-off clearly stated in README.md

This shows:
1. Cost awareness
2. Understanding of HA vs cost trade-offs
3. Ability to make pragmatic decisions for different environments

---

## Decision 7: Kubernetes Version

**Decision:** Use Kubernetes 1.31 (latest stable at time of writing).

**Rationale:**
- Shows commitment to staying current
- EKS supports 1.31 (released Sept 2024, EKS support added Oct 2024)
- Includes recent features: Pod Security Standards, HPA v2 improvements
- Demonstrates ability to work with modern Kubernetes

**Note:** Should be updated every 6-12 months as new versions are released.

---

## Decision 8: Metrics Collection (Metrics Server vs Prometheus)

**Decision:** Use Metrics Server for HPA, document Prometheus for custom metrics.

**Rationale:**
- Metrics Server is lightweight and sufficient for HPA
- Prometheus adds complexity (StatefulSet, persistent storage, Grafana)
- For portfolio demo, simpler is better
- Prometheus can be added later for custom metrics

**Implementation:**
- Metrics Server documented in k8s/cluster-ops/metrics-server.yaml
- Prometheus mentioned in docs for production use cases

---

## Decision 9: Cluster Logging Strategy

**Decision:** Enable control plane logging to CloudWatch, document container logging options.

**Rationale:**
- Control plane logs are critical for troubleshooting
- Minimal cost for control plane logs (~$5-10/month)
- Container logging (Fluent Bit → CloudWatch) adds cost and complexity
- For demo, `kubectl logs` is sufficient

**Future Enhancement:**
- Fluent Bit DaemonSet for centralized logging
- CloudWatch Insights or Elasticsearch for log analysis

---

## Decision 10: Cost vs Completeness

**Decision:** Prioritize demonstration of concepts over running every possible service.

**Philosophy:**
This is a portfolio piece that shows:
- Understanding of production-ready patterns
- Ability to make trade-off decisions
- Awareness of cost implications

**Examples:**
- ✅ Single NAT Gateway (demo) vs ⚙️ 3 NAT Gateways (prod)
- ✅ Metrics Server (lightweight) vs ⚙️ Full Prometheus stack
- ✅ kubectl logs vs ⚙️ Centralized logging (Fluent Bit)
- ✅ 2x t3.medium nodes vs ⚙️ Larger fleet

**Result:**
Monthly cost ~$150-200 instead of $500+ for full production setup.
- Lower barrier for reviewers to deploy
- Faster to tear down (docs/teardown.sh)
- Still demonstrates all core concepts

---

## Summary

These decisions reflect:
1. **Production readiness**: Using managed services, IRSA, network policies
2. **AWS ecosystem knowledge**: EKS, ALB, IAM, CloudWatch
3. **Security-first**: IRSA, Pod Security Standards, encryption, least privilege
4. **Cost awareness**: Pragmatic choices for demo vs production
5. **Operational maturity**: Monitoring, autoscaling, documented runbooks

Each decision is defensible in a technical interview and shows the ability to balance competing priorities.
