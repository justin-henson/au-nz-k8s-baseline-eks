#!/usr/bin/env bash
set -euo pipefail

# Validate EKS cluster health and readiness
#
# This script performs post-deployment health checks:
# - Verify all nodes are Ready
# - Check core system pods (CoreDNS, kube-proxy, etc.)
# - Test DNS resolution
# - Verify EKS add-ons are running
# - Check for any pod failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

FAILED_CHECKS=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EKS Cluster Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print check status
print_check() {
    local status=$1
    local message=$2

    if [ "${status}" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} ${message}"
    else
        echo -e "${RED}✗${NC} ${message}"
        ((FAILED_CHECKS++))
    fi
}

# Check 1: Verify kubectl is configured
echo -e "${YELLOW}Checking kubectl configuration...${NC}"
if kubectl cluster-info &>/dev/null; then
    CLUSTER_ENDPOINT=$(kubectl cluster-info | grep "control plane" | awk '{print $NF}')
    print_check 0 "kubectl is configured (${CLUSTER_ENDPOINT})"
else
    print_check 1 "kubectl is not configured or cannot reach cluster"
    echo "Run './scripts/connect.sh' to configure kubectl"
    exit 1
fi
echo ""

# Check 2: Verify nodes are Ready
echo -e "${YELLOW}Checking node status...${NC}"
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")

if [ "${NODE_COUNT}" -eq 0 ]; then
    print_check 1 "No nodes found"
elif [ "${NODE_COUNT}" -eq "${READY_NODES}" ]; then
    print_check 0 "All ${NODE_COUNT} nodes are Ready"
    kubectl get nodes -o wide
else
    print_check 1 "Only ${READY_NODES}/${NODE_COUNT} nodes are Ready"
    kubectl get nodes
fi
echo ""

# Check 3: Verify system pods
echo -e "${YELLOW}Checking system pods in kube-system...${NC}"
SYSTEM_PODS_TOTAL=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
SYSTEM_PODS_RUNNING=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "${SYSTEM_PODS_TOTAL}" -eq "${SYSTEM_PODS_RUNNING}" ]; then
    print_check 0 "All ${SYSTEM_PODS_TOTAL} system pods are Running"
else
    print_check 1 "Only ${SYSTEM_PODS_RUNNING}/${SYSTEM_PODS_TOTAL} system pods are Running"
    echo "Failed/Pending pods:"
    kubectl get pods -n kube-system | grep -v "Running\|Completed"
fi
echo ""

# Check 4: Verify CoreDNS
echo -e "${YELLOW}Checking CoreDNS...${NC}"
COREDNS_READY=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "${COREDNS_READY}" -ge 1 ]; then
    print_check 0 "CoreDNS is running (${COREDNS_READY} replicas)"
else
    print_check 1 "CoreDNS is not running"
fi
echo ""

# Check 5: Test DNS resolution
echo -e "${YELLOW}Testing DNS resolution...${NC}"
DNS_TEST=$(kubectl run dns-test --image=busybox:1.36 --rm -i --restart=Never --command -- nslookup kubernetes.default 2>&1 || echo "FAILED")
if echo "${DNS_TEST}" | grep -q "Server:"; then
    print_check 0 "DNS resolution is working"
else
    print_check 1 "DNS resolution failed"
    echo "${DNS_TEST}"
fi
echo ""

# Check 6: Verify EKS add-ons
echo -e "${YELLOW}Checking EKS add-ons...${NC}"
echo "Installed add-ons:"
kubectl get daemonsets,deployments -n kube-system | grep -E "coredns|kube-proxy|vpc-cni|ebs-csi" || echo "No standard add-ons found"
echo ""

# Check 7: Check for pod failures
echo -e "${YELLOW}Checking for failed pods across all namespaces...${NC}"
FAILED_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${FAILED_PODS}" -eq 0 ]; then
    print_check 0 "No failed pods found"
else
    print_check 1 "${FAILED_PODS} pods are not in Running/Succeeded state"
    kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded
fi
echo ""

# Check 8: Verify namespaces exist
echo -e "${YELLOW}Checking namespaces...${NC}"
EXPECTED_NAMESPACES=("demo-app" "monitoring")
for ns in "${EXPECTED_NAMESPACES[@]}"; do
    if kubectl get namespace "${ns}" &>/dev/null; then
        print_check 0 "Namespace '${ns}' exists"
    else
        print_check 1 "Namespace '${ns}' does not exist"
    fi
done
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
if [ "${FAILED_CHECKS}" -eq 0 ]; then
    echo -e "${GREEN}All checks passed! Cluster is healthy.${NC}"
    exit 0
else
    echo -e "${RED}${FAILED_CHECKS} check(s) failed. Please review the output above.${NC}"
    exit 1
fi
