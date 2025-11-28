#!/bin/bash
#===============================================================================
# Kubernetes Resilience Experiment - Setup Script
#===============================================================================
# This script sets up the complete experiment environment including:
# - Namespace creation
# - Application deployment (php-apache)
# - Horizontal Pod Autoscaler
# - Pod Disruption Budget
# - Locust load generator
#
# Designed for: Killercoda Kubernetes Playground
#===============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Header
echo "==============================================================================="
echo "    KUBERNETES RESILIENCE EXPERIMENT - ENVIRONMENT SETUP"
echo "==============================================================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connectivity
log_info "Checking cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
fi
log_success "Connected to Kubernetes cluster"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$PROJECT_DIR/k8s"

# Step 1: Create namespace
log_info "Creating experiment namespace..."
kubectl apply -f "$K8S_DIR/namespace.yaml"
log_success "Namespace 'k8s-resilience-experiment' created"

# Step 2: Deploy php-apache application
log_info "Deploying php-apache application..."
kubectl apply -f "$K8S_DIR/php-apache-deployment.yaml"
log_success "php-apache deployment and services created"

# Step 3: Apply Horizontal Pod Autoscaler
log_info "Configuring Horizontal Pod Autoscaler..."
kubectl apply -f "$K8S_DIR/hpa.yaml"
log_success "HPA configured (min: 3, max: 10 replicas)"

# Step 4: Apply Pod Disruption Budget
log_info "Configuring Pod Disruption Budget..."
kubectl apply -f "$K8S_DIR/pod-disruption-budget.yaml"
log_success "PDB configured (minAvailable: 2)"

# Step 5: Create ConfigMap for Locust scripts
log_info "Creating Locust scripts ConfigMap..."
kubectl create configmap locust-scripts \
    --from-file="$PROJECT_DIR/locust/locustfile.py" \
    -n k8s-resilience-experiment \
    --dry-run=client -o yaml | kubectl apply -f -
log_success "Locust scripts ConfigMap created"

# Step 6: Deploy Locust load generator
log_info "Deploying Locust load generator..."
kubectl apply -f "$K8S_DIR/locust-deployment.yaml"
log_success "Locust master and workers deployed"

# Wait for deployments to be ready
log_info "Waiting for deployments to be ready..."
echo ""

log_info "Waiting for php-apache pods..."
kubectl rollout status deployment/php-apache -n k8s-resilience-experiment --timeout=120s

log_info "Waiting for Locust master..."
kubectl rollout status deployment/locust-master -n k8s-resilience-experiment --timeout=120s

log_info "Waiting for Locust workers..."
kubectl rollout status deployment/locust-worker -n k8s-resilience-experiment --timeout=120s

echo ""
log_success "All deployments are ready!"

# Display cluster status
echo ""
echo "==============================================================================="
echo "    EXPERIMENT ENVIRONMENT STATUS"
echo "==============================================================================="
echo ""

log_info "Pods in experiment namespace:"
kubectl get pods -n k8s-resilience-experiment -o wide
echo ""

log_info "Services:"
kubectl get svc -n k8s-resilience-experiment
echo ""

log_info "HPA Status:"
kubectl get hpa -n k8s-resilience-experiment
echo ""

# Get access URLs
echo ""
echo "==============================================================================="
echo "    ACCESS INFORMATION"
echo "==============================================================================="
echo ""

# Get node IP (for Killercoda)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "PHP-Apache Service: http://${NODE_IP}:30080"
echo "Locust Web UI:      http://${NODE_IP}:30089"
echo ""
echo "In Killercoda, you can access services using the Traffic/Ports feature"
echo "Configure port 30089 for Locust UI and port 30080 for the application"
echo ""

echo "==============================================================================="
echo "    SETUP COMPLETE - READY FOR EXPERIMENT"
echo "==============================================================================="
echo ""
echo "Next steps:"
echo "  1. Access Locust UI at port 30089"
echo "  2. Start a load test with 50-100 users"
echo "  3. Run failure simulation scripts in another terminal"
echo "  4. Observe Kubernetes self-healing behavior"
echo ""

