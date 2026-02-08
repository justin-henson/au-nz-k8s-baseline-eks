I need you to build a complete GitHub repository called "au-nz-k8s-baseline-eks" that demonstrates a production-ready EKS cluster provisioned with Terraform, with Kubernetes manifests for a baseline workload. This is for my AU/NZ DevOps job search portfolio (GitHub: justin-henson).

## CONTEXT
Kubernetes is in nearly every AU/NZ DevOps job listing. Employers want EKS/AKS experience. I already have an AWS Terraform baseline (au-nz-cloud-baseline-aws) and a CI/CD pipeline repo (au-nz-cicd-pipeline). This repo shows I can provision and operate Kubernetes — the missing container orchestration piece.

## REPOSITORY STRUCTURE

au-nz-k8s-baseline-eks/
├── README.md
├── LICENSE                              # MIT
├── terraform/
│   ├── main.tf                          # Root: VPC + EKS cluster + node group
│   ├── variables.tf                     # Cluster name, region, node sizing, etc.
│   ├── outputs.tf                       # Cluster endpoint, kubeconfig command, OIDC provider ARN
│   ├── providers.tf
│   ├── versions.tf
│   ├── vpc.tf                           # VPC with public/private subnets using terraform-aws-modules/vpc
│   ├── eks.tf                           # EKS cluster using terraform-aws-modules/eks (latest stable)
│   ├── iam.tf                           # IRSA setup for workloads (IAM Roles for Service Accounts)
│   └── addons.tf                        # EKS add-ons: CoreDNS, kube-proxy, vpc-cni, ebs-csi-driver
├── k8s/
│   ├── namespaces/
│   │   ├── demo-app.yaml                # Namespace with resource quota + limit range
│   │   └── monitoring.yaml              # Namespace for observability stack
│   ├── demo-app/
│   │   ├── deployment.yaml              # nginx or httpbin — simple, verifiable
│   │   ├── service.yaml                 # ClusterIP service
│   │   ├── ingress.yaml                 # ALB Ingress (aws-load-balancer-controller annotations)
│   │   ├── hpa.yaml                     # Horizontal Pod Autoscaler
│   │   └── network-policy.yaml          # Default deny + allow specific traffic
│   ├── security/
│   │   ├── pod-security-standards.yaml  # Pod Security Standards (restricted baseline)
│   │   └── rbac.yaml                    # Example ClusterRole + RoleBinding for a dev team
│   └── cluster-ops/
│       ├── aws-lb-controller.yaml       # AWS Load Balancer Controller setup notes/manifest
│       ├── metrics-server.yaml          # Metrics server for HPA
│       └── cluster-autoscaler.yaml      # Cluster Autoscaler config
├── scripts/
│   ├── connect.sh                       # aws eks update-kubeconfig wrapper
│   ├── validate-cluster.sh              # Post-deploy health checks (nodes ready, DNS working, etc.)
│   └── teardown.sh                      # Ordered teardown: k8s resources → terraform destroy
├── docs/
│   ├── ARCHITECTURE.md                  # Mermaid diagram: VPC → subnets → EKS → node groups → pods → ALB
│   ├── DECISION-LOG.md                  # Design decisions (see below)
│   ├── COST-ESTIMATE.md                 # Rough monthly cost breakdown so reviewers know before deploying
│   └── UPGRADE-RUNBOOK.md              # How to upgrade EKS version safely (ties to ops-runbooks style)
└── .github/
    └── workflows/
        └── validate.yml                 # CI: terraform validate + fmt check + k8s manifest validation (kubeval/kubeconform)

## TERRAFORM REQUIREMENTS

### VPC (vpc.tf)
- Use terraform-aws-modules/vpc/aws
- 3 AZs, public + private subnets
- NAT Gateway (single for cost in demo, note that prod would use one per AZ)
- Tag subnets correctly for EKS auto-discovery:
  - Private: kubernetes.io/role/internal-elb = 1
  - Public: kubernetes.io/role/elb = 1

### EKS (eks.tf)
- Use terraform-aws-modules/eks/aws (v20+)
- Kubernetes version: 1.31 or latest stable
- Managed node group: 2 nodes (t3.medium), min 1 / max 4
- Enable OIDC provider (for IRSA)
- Enable cluster logging: api, audit, authenticator
- Enable envelope encryption for secrets (KMS)
- Cluster endpoint: private + public (public restricted to deployer IP, with a variable)
- Include EKS access entries for cluster admin

### Add-ons (addons.tf)
- CoreDNS, kube-proxy, vpc-cni as EKS managed add-ons
- EBS CSI driver with IRSA

### IAM (iam.tf)
- IRSA example: create an IAM role that a Kubernetes ServiceAccount can assume
- Show the trust policy pattern clearly
- This is a key interview talking point — make it exemplary

## KUBERNETES MANIFESTS REQUIREMENTS

### demo-app/
- Deployment: 2 replicas, resource requests/limits set, readiness + liveness probes, security context (non-root, read-only root filesystem, drop all capabilities)
- Service: ClusterIP
- Ingress: AWS ALB annotations (scheme: internet-facing, target-type: ip, healthcheck path)
- HPA: scale on CPU 70%, min 2 / max 6
- Network Policy: default deny ingress, allow only from specific namespace

### security/
- Pod Security Standards: enforce "restricted" on demo-app namespace
- RBAC: a "dev-team" ClusterRole with read access to pods, logs, deployments; RoleBinding in demo-app namespace

### cluster-ops/
- Each file should be well-commented setup notes + manifests
- Include helm install commands as comments where appropriate (e.g., aws-lb-controller via Helm)
- Metrics server manifest or Helm install command
- Cluster autoscaler config pointing to the right ASG

## DOCS REQUIREMENTS

### ARCHITECTURE.md
- Mermaid diagram showing: Internet → ALB → Ingress → Service → Pods ← HPA, with VPC/subnet/node group context
- Brief explanation of each layer

### DECISION-LOG.md
Cover these decisions:
1. EKS vs self-managed Kubernetes vs Fargate
2. Managed node groups vs self-managed vs Karpenter
3. IRSA vs node-level IAM roles
4. ALB Ingress Controller vs Nginx Ingress
5. Network policy approach

### COST-ESTIMATE.md
- Monthly estimate for: EKS control plane, 2x t3.medium nodes, NAT Gateway, ALB
- Total estimate and note about what can be scaled down for demo

### UPGRADE-RUNBOOK.md
- Step-by-step EKS version upgrade procedure
- Pre-upgrade checks, upgrade order (control plane → add-ons → node groups), post-upgrade validation
- Rollback considerations

## README.md
- Title: "Kubernetes Baseline — EKS with Terraform"
- Architecture diagram (Mermaid)
- "Quick Review for Hiring Managers" section (where to look in 60 seconds)
- "Deploy It Yourself" section with prerequisites and step-by-step
- "What This Proves" section: cluster provisioning, security hardening, workload deployment, autoscaling, IRSA
- "Connects To" section linking to au-nz-cloud-baseline-aws (networking patterns), au-nz-cicd-pipeline (how this would be deployed via pipeline), au-nz-ops-runbooks (operational procedures)
- Cost warning before deploy

## CODE QUALITY
- All Terraform: pinned versions, passes fmt + validate
- All YAML: valid k8s manifests (would pass kubeconform)
- Comments explain WHY not WHAT
- Security-first defaults (non-root pods, network policies, IRSA over node roles, encrypted secrets)

## TONE
Senior engineer explaining architecture to a peer. Show trade-off thinking. Don't just deploy — show you understand WHY each piece exists.

Build the complete repository now. Every file, fully written, ready to push to GitHub.
