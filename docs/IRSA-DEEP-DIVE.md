# IRSA Deep Dive — IAM Roles for Service Accounts

This document explains how IRSA works in this cluster, why it matters, and how it compares
to other approaches for granting AWS access to Kubernetes pods.

## The Problem

Kubernetes pods running on EKS often need access to AWS services — S3 buckets, DynamoDB tables,
SQS queues, Secrets Manager. The question is: how do you grant that access securely?

## Approaches Compared

### Node-Level IAM Role (Legacy)

Every pod on a node inherits the node's IAM role. If one pod needs S3 access, every pod
on that node gets S3 access.

**Problems:**
- Violates least privilege — all pods share the same permissions
- A compromised pod can access any AWS service the node role allows
- No way to audit which pod made which API call
- Adding permissions for one workload exposes all workloads

### kiam / kube2iam (Workaround)

Third-party tools that intercept metadata requests and return pod-specific credentials.

**Problems:**
- Adds infrastructure complexity (DaemonSet on every node)
- Single point of failure for all AWS API calls
- Race conditions during pod startup
- Maintenance burden for a third-party component

### IRSA (Current Standard)

Each Kubernetes ServiceAccount is mapped to a specific IAM role. Pods using that
ServiceAccount receive short-lived credentials scoped to only that role.

**How it works:**

```
1. EKS creates an OIDC provider for the cluster
2. IAM role trust policy references the OIDC provider + specific ServiceAccount
3. Pod spec references the ServiceAccount
4. EKS injects a projected service account token into the pod
5. AWS STS validates the token against the OIDC provider
6. Pod receives temporary credentials for only the mapped IAM role
```

## How IRSA Is Configured in This Cluster

### Step 1: OIDC Provider

Terraform creates an OIDC provider linked to the EKS cluster:

```hcl
# Created automatically by the EKS module
# The OIDC issuer URL is unique to each cluster
resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}
```

### Step 2: IAM Role with Trust Policy

The trust policy restricts which ServiceAccount can assume the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:NAMESPACE:SA_NAME",
          "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

The two conditions are critical:

- **`:sub`** — restricts to a specific ServiceAccount in a specific namespace
- **`:aud`** — restricts the audience to STS (prevents token reuse)

### Step 3: Kubernetes ServiceAccount Annotation

The ServiceAccount is annotated with the IAM role ARN:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: demo-app-sa
  namespace: demo-app
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/baseline-eks-demo-app-irsa
```

### Step 4: Pod Receives Credentials

When a pod starts with this ServiceAccount, EKS automatically:

1. Mounts a projected token at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
2. Sets `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` environment variables
3. AWS SDKs automatically detect these and call `sts:AssumeRoleWithWebIdentity`

No code changes needed — the AWS SDK handles credential exchange transparently.

## Security Properties

| Property | Node IAM | kiam/kube2iam | IRSA |
|----------|----------|---------------|------|
| Per-pod permissions | No | Yes | Yes |
| No extra infrastructure | Yes | No | Yes |
| Short-lived credentials | No | Yes | Yes |
| CloudTrail attribution | Node only | Pod level | Pod level |
| Works with Fargate | N/A | No | Yes |
| AWS-native support | Yes | No | Yes |

## Verifying IRSA Is Working

From inside a pod with IRSA configured:

```bash
# Check environment variables are set
env | grep AWS

# Expected output:
# AWS_ROLE_ARN=arn:aws:iam::ACCOUNT:role/baseline-eks-demo-app-irsa
# AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token

# Verify the assumed identity
aws sts get-caller-identity

# Expected: shows the IRSA role ARN, not the node role
```

## Common Mistakes

**Forgetting the audience condition** — without the `:aud` check, any OIDC token
from the cluster could assume the role, not just tokens intended for STS.

**Wrong namespace in trust policy** — the `:sub` condition includes the namespace.
If you move a ServiceAccount to a different namespace, the trust policy must be updated.

**Using a wildcard in the subject** — setting `:sub` to `system:serviceaccount:*:*`
defeats the purpose. Always specify the exact namespace and ServiceAccount name.

**Not testing after changes** — always run `aws sts get-caller-identity` from inside
the pod after modifying IRSA configuration to confirm the correct role is assumed.
