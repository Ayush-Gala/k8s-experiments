#!/bin/bash
#===============================================================================
# Kubernetes Resilience Experiment - Cleanup Script
#===============================================================================
# Removes all experiment resources from the cluster
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="k8s-resilience-experiment"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "==============================================================================="
echo "    KUBERNETES RESILIENCE EXPERIMENT - CLEANUP"
echo "==============================================================================="
echo ""

log_warning "This will delete all experiment resources including:"
echo "  - Namespace: $NAMESPACE"
echo "  - All deployments, services, and pods"
echo "  - HPA and PDB configurations"
echo ""

read -p "Are you sure you want to proceed? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

# Remove any taints we might have added
log_info "Removing experiment taints from nodes..."
for NODE in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl taint nodes $NODE experiment=failure:NoSchedule- 2>/dev/null || true
done

# Uncordon any cordoned nodes
log_info "Uncordoning all nodes..."
for NODE in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl uncordon $NODE 2>/dev/null || true
done

# Delete namespace (this removes everything in it)
log_info "Deleting namespace and all resources..."
kubectl delete namespace $NAMESPACE --timeout=120s 2>/dev/null || true

log_success "Cleanup complete!"
echo ""
log_info "Verifying cleanup..."
kubectl get all -n $NAMESPACE 2>/dev/null || echo "  Namespace successfully deleted"
echo ""

