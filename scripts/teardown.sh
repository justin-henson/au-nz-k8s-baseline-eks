#!/usr/bin/env bash
set -euo pipefail

# Teardown EKS cluster and all resources
#
# This script performs an ordered teardown to avoid resource deletion issues:
# 1. Delete Kubernetes resources (LoadBalancers, PVCs, etc.)
# 2. Wait for AWS resources to be cleaned up (ELBs, EBS volumes)
# 3. Run terraform destroy
#
# This prevents common issues like:
# - VPC deletion blocked by leftover ENIs from LoadBalancers
# - Security group deletion blocked by dependencies
# - Subnet deletion blocked by lingering EBS volumes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EKS Cluster Teardown${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Confirmation prompt
echo -e "${YELLOW}WARNING: This will destroy all cluster resources!${NC}"
echo "This action cannot be undone."
echo ""
read -p "Are you sure you want to proceed? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Teardown cancelled."
    exit 0
fi

# Step 1: Delete Kubernetes resources that create AWS resources
echo -e "${GREEN}Step 1: Deleting Kubernetes resources...${NC}"
echo ""

if kubectl cluster-info &>/dev/null; then
    echo "Deleting Ingress resources (ALBs)..."
    kubectl delete ingress --all --all-namespaces --ignore-not-found=true --wait=true --timeout=5m || true

    echo "Deleting LoadBalancer Services (NLBs)..."
    kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer --ignore-not-found=true --wait=true --timeout=5m || true

    echo "Deleting PersistentVolumeClaims (EBS volumes)..."
    kubectl delete pvc --all --all-namespaces --ignore-not-found=true --wait=true --timeout=5m || true

    echo "Deleting demo-app namespace..."
    kubectl delete namespace demo-app --ignore-not-found=true --wait=true --timeout=5m || true

    echo "Deleting monitoring namespace..."
    kubectl delete namespace monitoring --ignore-not-found=true --wait=true --timeout=5m || true

    echo -e "${GREEN}✓ Kubernetes resources deleted${NC}"
else
    echo -e "${YELLOW}⚠ Cannot connect to cluster. Skipping Kubernetes resource deletion.${NC}"
    echo "This may cause issues with Terraform destroy if there are leftover AWS resources."
fi
echo ""

# Step 2: Wait for AWS resources to be cleaned up
echo -e "${GREEN}Step 2: Waiting for AWS resources to be cleaned up...${NC}"
echo "Waiting 60 seconds for ELBs and ENIs to be fully deleted..."
sleep 60
echo -e "${GREEN}✓ Wait complete${NC}"
echo ""

# Step 3: Run terraform destroy
echo -e "${GREEN}Step 3: Running terraform destroy...${NC}"
echo ""

cd "${TERRAFORM_DIR}"

if [ ! -f "terraform.tfstate" ]; then
    echo -e "${YELLOW}⚠ No Terraform state found. Nothing to destroy.${NC}"
    exit 0
fi

echo "Running terraform destroy..."
if terraform destroy -auto-approve; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Teardown complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Terraform destroy failed!${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Common issues:"
    echo "1. Leftover ENIs from LoadBalancers - wait longer and retry"
    echo "2. Security group dependencies - check for leftover resources"
    echo "3. EBS volumes not deleted - manually delete in AWS Console"
    echo ""
    echo "You can manually clean up resources in the AWS Console and retry:"
    echo "  cd terraform && terraform destroy"
    exit 1
fi
