#!/usr/bin/env bash
set -euo pipefail

# Connect to EKS cluster by updating kubeconfig
#
# This script is a wrapper around `aws eks update-kubeconfig` that:
# - Sets the correct AWS region
# - Uses the cluster name from Terraform outputs
# - Verifies connectivity after updating kubeconfig

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Connecting to EKS cluster...${NC}"

# Check if Terraform state exists
if [ ! -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    echo -e "${RED}Error: Terraform state not found.${NC}"
    echo "Please run 'terraform apply' first to create the cluster."
    exit 1
fi

# Get cluster details from Terraform outputs
cd "${TERRAFORM_DIR}"

CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
AWS_REGION=$(terraform output -json | jq -r '.configure_kubectl.value' | grep -oP '(?<=--region )[^ ]+' || echo "ap-southeast-2")

if [ -z "${CLUSTER_NAME}" ]; then
    echo -e "${RED}Error: Could not retrieve cluster name from Terraform outputs.${NC}"
    exit 1
fi

echo "Cluster Name: ${CLUSTER_NAME}"
echo "AWS Region: ${AWS_REGION}"

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig...${NC}"
aws eks update-kubeconfig \
    --region "${AWS_REGION}" \
    --name "${CLUSTER_NAME}" \
    --alias "${CLUSTER_NAME}"

# Verify connectivity
echo -e "${YELLOW}Verifying connectivity...${NC}"
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓ Successfully connected to cluster${NC}"
    echo ""
    kubectl cluster-info
    echo ""
    echo "Current context: $(kubectl config current-context)"
    echo ""
    echo -e "${GREEN}You can now run kubectl commands.${NC}"
else
    echo -e "${RED}✗ Failed to connect to cluster${NC}"
    echo "Please check your AWS credentials and cluster status."
    exit 1
fi
