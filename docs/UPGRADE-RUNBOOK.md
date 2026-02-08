# EKS Upgrade Runbook

This runbook provides step-by-step procedures for upgrading an EKS cluster version safely. It follows AWS best practices and includes pre-upgrade checks, the upgrade process, and post-upgrade validation.

---

## Overview

**Upgrade Order:**
1. Pre-upgrade checks and backups
2. Control plane upgrade
3. Add-ons upgrade (CoreDNS, kube-proxy, VPC CNI)
4. Node groups upgrade
5. Post-upgrade validation
6. Rollback procedure (if needed)

**Downtime:** Minimal to none for applications with proper HA configuration (multiple replicas, pod disruption budgets).

**Upgrade Frequency:** AWS supports each Kubernetes version for ~14 months. Plan to upgrade at least once per year.

---

## Pre-Upgrade Checks

### 1. Review Version Compatibility

**Check current version:**
```bash
kubectl version --short
aws eks describe-cluster --name baseline-eks --query 'cluster.version' --output text
```

**EKS version support:**
- 1.31 → 1.32: Supported (latest)
- 1.30 → 1.31: Supported
- Skipping versions (1.29 → 1.31): NOT supported

**Check Kubernetes deprecations:**
- Review [Kubernetes deprecation guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)
- Check for deprecated APIs used by your workloads:
  ```bash
  kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
  ```

### 2. Backup Critical Data

**Backup etcd (control plane):**
- EKS manages etcd backups automatically
- Take manual snapshots if needed:
  ```bash
  aws eks describe-cluster --name baseline-eks > cluster-backup-$(date +%Y%m%d).json
  ```

**Backup Kubernetes resources:**
```bash
# Backup all resources in all namespaces
kubectl get all --all-namespaces -o yaml > k8s-backup-$(date +%Y%m%d).yaml

# Or use velero for comprehensive backups
velero backup create pre-upgrade-backup --include-namespaces demo-app,monitoring
```

**Backup Terraform state:**
```bash
cd terraform
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)
```

### 3. Check Cluster Health

**Verify all nodes are Ready:**
```bash
kubectl get nodes
```

**Check for pod issues:**
```bash
kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded
```

**Verify system pods:**
```bash
kubectl get pods -n kube-system
```

**Check recent events:**
```bash
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20
```

### 4. Review Application Configuration

**Check resource requests/limits:**
- Ensure all pods have resource requests set
- HPA requires requests for autoscaling

**Check PodDisruptionBudgets:**
```bash
kubectl get pdb --all-namespaces
```

If missing, create PDBs for critical applications:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: demo-app-pdb
  namespace: demo-app
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: demo-app
```

### 5. Check Add-on Compatibility

**List current add-on versions:**
```bash
aws eks describe-addon-versions --kubernetes-version 1.31 --addon-name vpc-cni
aws eks describe-addon-versions --kubernetes-version 1.31 --addon-name coredns
aws eks describe-addon-versions --kubernetes-version 1.31 --addon-name kube-proxy
aws eks describe-addon-versions --kubernetes-version 1.31 --addon-name aws-ebs-csi-driver
```

**Check installed versions:**
```bash
aws eks list-addons --cluster-name baseline-eks
aws eks describe-addon --cluster-name baseline-eks --addon-name vpc-cni
```

### 6. Schedule Maintenance Window

**Recommended timing:**
- Non-peak hours
- Have team available for rollback if needed
- Allow 2-4 hours for full upgrade process

**Communication:**
- Notify stakeholders of maintenance window
- Prepare status page update
- Have rollback plan ready

---

## Step 1: Upgrade Control Plane

### Option A: Using Terraform (Recommended)

**Update Terraform configuration:**
```hcl
# terraform/variables.tf
variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.32"  # Update this
}
```

**Plan and apply:**
```bash
cd terraform
terraform plan -out=upgrade.tfplan
# Review the plan carefully
terraform apply upgrade.tfplan
```

### Option B: Using AWS CLI

```bash
aws eks update-cluster-version \
  --name baseline-eks \
  --kubernetes-version 1.32
```

**Monitor upgrade progress:**
```bash
aws eks describe-update \
  --name baseline-eks \
  --update-id UPDATE_ID

# Or watch cluster status
watch -n 10 'aws eks describe-cluster --name baseline-eks --query "cluster.status"'
```

**Expected duration:** 20-30 minutes for control plane upgrade.

### Verify Control Plane Upgrade

```bash
# Check control plane version
aws eks describe-cluster --name baseline-eks --query 'cluster.version'

# Check API server is responsive
kubectl version --short

# Check cluster info
kubectl cluster-info
```

---

## Step 2: Upgrade EKS Add-ons

### 2.1 Update VPC CNI

```bash
# Get latest compatible version
aws eks describe-addon-versions \
  --kubernetes-version 1.32 \
  --addon-name vpc-cni \
  --query 'addons[0].addonVersions[0].addonVersion' \
  --output text

# Update add-on
aws eks update-addon \
  --cluster-name baseline-eks \
  --addon-name vpc-cni \
  --addon-version v1.18.0-eksbuild.1 \
  --resolve-conflicts OVERWRITE
```

**Monitor:**
```bash
aws eks describe-addon --cluster-name baseline-eks --addon-name vpc-cni --query 'addon.status'
kubectl get pods -n kube-system -l k8s-app=aws-node
```

### 2.2 Update CoreDNS

```bash
# Get latest version
aws eks describe-addon-versions \
  --kubernetes-version 1.32 \
  --addon-name coredns \
  --query 'addons[0].addonVersions[0].addonVersion' \
  --output text

# Update
aws eks update-addon \
  --cluster-name baseline-eks \
  --addon-name coredns \
  --addon-version v1.11.1-eksbuild.4 \
  --resolve-conflicts OVERWRITE
```

**Test DNS after update:**
```bash
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes.default
```

### 2.3 Update kube-proxy

```bash
# Get latest version
aws eks describe-addon-versions \
  --kubernetes-version 1.32 \
  --addon-name kube-proxy \
  --query 'addons[0].addonVersions[0].addonVersion' \
  --output text

# Update
aws eks update-addon \
  --cluster-name baseline-eks \
  --addon-name kube-proxy \
  --addon-version v1.30.0-eksbuild.3 \
  --resolve-conflicts OVERWRITE
```

### 2.4 Update EBS CSI Driver

```bash
aws eks update-addon \
  --cluster-name baseline-eks \
  --addon-name aws-ebs-csi-driver \
  --addon-version v1.34.0-eksbuild.1 \
  --resolve-conflicts OVERWRITE \
  --service-account-role-arn $(terraform output -raw ebs_csi_driver_role_arn)
```

**Verify all add-ons:**
```bash
kubectl get daemonsets -n kube-system
kubectl get deployments -n kube-system
```

---

## Step 3: Upgrade Node Groups

### 3.1 Prepare for Node Upgrade

**Check node versions:**
```bash
kubectl get nodes -o wide
```

**Cordon nodes (optional, prevents new pods):**
```bash
kubectl cordon <node-name>
```

### 3.2 Upgrade Managed Node Group

**Option A: Using Terraform (Recommended)**

Terraform will automatically trigger rolling update when control plane version changes:

```bash
cd terraform
terraform plan
terraform apply
```

**Option B: Using AWS CLI**

```bash
aws eks update-nodegroup-version \
  --cluster-name baseline-eks \
  --nodegroup-name nodes \
  --launch-template name=nodes,version=\$Latest
```

**Monitor upgrade:**
```bash
aws eks describe-nodegroup-update \
  --cluster-name baseline-eks \
  --nodegroup-name nodes \
  --update-id UPDATE_ID

# Watch nodes
watch -n 10 'kubectl get nodes'
```

### 3.3 Rolling Update Process

EKS performs rolling updates automatically:
1. New node with updated AMI is launched
2. Old node is cordoned (no new pods scheduled)
3. Pods on old node are evicted (respecting PDBs)
4. Pods are rescheduled on new nodes
5. Old node is terminated
6. Process repeats for each node

**Expected duration:** 10-15 minutes per node.

### 3.4 Monitor Pod Eviction

```bash
# Watch pods during node drain
kubectl get pods --all-namespaces -o wide --watch

# Check for evicted pods
kubectl get pods --all-namespaces --field-selector=status.phase=Failed
```

---

## Step 4: Post-Upgrade Validation

### 4.1 Verify Cluster Version

```bash
# Control plane version
aws eks describe-cluster --name baseline-eks --query 'cluster.version'

# Node versions
kubectl get nodes -o wide

# Server version via kubectl
kubectl version --short
```

### 4.2 Run Validation Script

```bash
./scripts/validate-cluster.sh
```

### 4.3 Application Health Checks

**Check demo app:**
```bash
kubectl get pods -n demo-app
kubectl logs -n demo-app -l app=demo-app --tail=50

# Test application endpoint
curl https://your-alb-url.elb.amazonaws.com/status/200
```

**Check HPA:**
```bash
kubectl get hpa -n demo-app
```

**Check ingress:**
```bash
kubectl get ingress -n demo-app
```

### 4.4 Performance Validation

**Test autoscaling:**
```bash
# Generate load
kubectl run load-generator --image=busybox:1.36 --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://demo-app.demo-app.svc.cluster.local; done"

# Watch HPA scale
watch kubectl get hpa -n demo-app

# Cleanup
kubectl delete pod load-generator
```

**Check metrics:**
```bash
kubectl top nodes
kubectl top pods -n demo-app
```

### 4.5 Review Logs

**Check control plane logs in CloudWatch:**
```bash
aws logs tail /aws/eks/baseline-eks/cluster --follow
```

**Check add-on logs:**
```bash
kubectl logs -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=aws-node
```

---

## Rollback Procedure

If critical issues are discovered after upgrade:

### 1. Assess Impact
- Is the issue blocking production workloads?
- Can it be mitigated with configuration changes?
- Is rollback the only option?

### 2. Rollback Control Plane (Not Recommended)

**⚠️ WARNING:** EKS does not support downgrading control plane version.

**Options:**
- Restore from backup (requires new cluster)
- Fix forward (patch issues, update workloads)

### 3. Rollback Node Groups

If nodes are the issue, you can rollback node group AMI:

```bash
# Using Terraform
cd terraform
git checkout HEAD~1 terraform/eks.tf  # Restore previous config
terraform apply

# Using AWS CLI
aws eks update-nodegroup-version \
  --cluster-name baseline-eks \
  --nodegroup-name nodes \
  --launch-template name=nodes,version=PREVIOUS_VERSION
```

### 4. Rollback Add-ons

```bash
aws eks update-addon \
  --cluster-name baseline-eks \
  --addon-name vpc-cni \
  --addon-version PREVIOUS_VERSION \
  --resolve-conflicts OVERWRITE
```

### 5. Rollback Application Manifests

```bash
kubectl apply -f k8s/  # Restore previous manifests from git
```

---

## Troubleshooting

### Issue: Nodes not joining cluster after upgrade

**Symptoms:** New nodes appear in EC2 but not in `kubectl get nodes`

**Resolution:**
1. Check node IAM role has correct trust policy
2. Verify aws-auth ConfigMap:
   ```bash
   kubectl get configmap aws-auth -n kube-system -o yaml
   ```
3. Check node logs in EC2 instance:
   ```bash
   ssh ec2-user@NODE_IP
   journalctl -u kubelet -f
   ```

### Issue: Pods failing to schedule

**Symptoms:** Pods stuck in Pending state

**Resolution:**
1. Check node capacity:
   ```bash
   kubectl describe nodes | grep -A5 "Allocated resources"
   ```
2. Check pod events:
   ```bash
   kubectl describe pod POD_NAME -n NAMESPACE
   ```
3. Check for taints:
   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
   ```

### Issue: CoreDNS not resolving

**Symptoms:** DNS lookups fail, pods can't reach services

**Resolution:**
1. Check CoreDNS pods:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   kubectl logs -n kube-system -l k8s-app=kube-dns
   ```
2. Test DNS:
   ```bash
   kubectl run dns-test --image=busybox:1.36 --rm -it -- nslookup kubernetes.default
   ```
3. Restart CoreDNS:
   ```bash
   kubectl rollout restart deployment coredns -n kube-system
   ```

---

## Upgrade Checklist

- [ ] Review Kubernetes version compatibility
- [ ] Check for deprecated APIs in workloads
- [ ] Backup Terraform state
- [ ] Backup Kubernetes resources
- [ ] Verify cluster health (nodes, pods, events)
- [ ] Create PodDisruptionBudgets for critical apps
- [ ] Schedule maintenance window
- [ ] Notify stakeholders
- [ ] Upgrade control plane
- [ ] Verify control plane upgrade
- [ ] Upgrade VPC CNI add-on
- [ ] Upgrade CoreDNS add-on
- [ ] Upgrade kube-proxy add-on
- [ ] Upgrade EBS CSI driver add-on
- [ ] Verify all add-ons are running
- [ ] Upgrade managed node group
- [ ] Monitor node rolling update
- [ ] Run validation script
- [ ] Verify application health
- [ ] Test autoscaling
- [ ] Review logs for errors
- [ ] Update documentation (version numbers)
- [ ] Notify stakeholders of completion

---

## References

- [EKS User Guide - Updating Clusters](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html)
- [Kubernetes Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/)
- [EKS Kubernetes Versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [AWS EKS Best Practices - Upgrades](https://aws.github.io/aws-eks-best-practices/upgrades/)
