#!/bin/bash
#===============================================================================
# Kubernetes Resilience Experiment - Setup Script
#===============================================================================
# This script sets up the complete experiment environment including:
# - Metrics Server (for HPA CPU metrics)
# - Namespace creation
# - Application deployment (php-apache)
# - Horizontal Pod Autoscaler
# - Pod Disruption Budget
# - Local Locust installation (python3-locust)
#
# Designed for: Killercoda Kubernetes Playground
#===============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
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
LOCUST_DIR="$PROJECT_DIR/locust"

#===============================================================================
# STEP 1: Install Metrics Server (required for HPA)
#===============================================================================
echo ""
log_step "STEP 1: Installing Metrics Server for HPA support..."
echo ""

# Check if metrics-server is already installed
if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
    log_info "Metrics server already installed, checking if it needs patching..."
else
    log_info "Downloading metrics-server manifest..."
    
    # Download metrics-server manifest
    curl -sL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml -o /tmp/metrics-server.yaml
    
    # Add --kubelet-insecure-tls flag for Killercoda/playground environments
    log_info "Patching metrics-server for insecure TLS (required for Killercoda)..."
    sed -i '/- --metric-resolution=15s/a\        - --kubelet-insecure-tls' /tmp/metrics-server.yaml
    
    # Apply metrics-server
    log_info "Applying metrics-server..."
    kubectl apply -f /tmp/metrics-server.yaml
    
    # Clean up
    rm -f /tmp/metrics-server.yaml
fi

log_info "Waiting for metrics-server to be ready..."
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s || {
    log_warning "Metrics server taking longer than expected. Continuing..."
}

# Verify metrics are available (may take a moment)
log_info "Verifying metrics API (may take 30-60 seconds to populate)..."
sleep 10
if kubectl top nodes &> /dev/null; then
    log_success "Metrics server is working!"
else
    log_warning "Metrics not yet available. They should appear within 1-2 minutes."
fi

#===============================================================================
# STEP 2: Install Locust locally
#===============================================================================
echo ""
log_step "STEP 2: Installing Locust load generator locally..."
echo ""

if command -v locust &> /dev/null; then
    log_info "Locust is already installed"
    locust --version
else
    log_info "Installing python3-locust via apt..."
    apt-get update -qq
    apt-get install -y -qq python3-locust
    log_success "Locust installed successfully"
fi

#===============================================================================
# STEP 3: Create Kubernetes namespace
#===============================================================================
echo ""
log_step "STEP 3: Creating experiment namespace..."
echo ""

kubectl apply -f "$K8S_DIR/namespace.yaml"
log_success "Namespace 'k8s-resilience-experiment' created"

#===============================================================================
# STEP 4: Deploy php-apache application
#===============================================================================
echo ""
log_step "STEP 4: Deploying php-apache application..."
echo ""

kubectl apply -f "$K8S_DIR/php-apache-deployment.yaml"
log_success "php-apache deployment and services created"

#===============================================================================
# STEP 5: Configure Horizontal Pod Autoscaler
#===============================================================================
echo ""
log_step "STEP 5: Configuring Horizontal Pod Autoscaler..."
echo ""

kubectl apply -f "$K8S_DIR/hpa.yaml"
log_success "HPA configured (min: 3, max: 100 replicas, target: 50% CPU)"

#===============================================================================
# STEP 6: Configure Pod Disruption Budget
#===============================================================================
echo ""
log_step "STEP 6: Configuring Pod Disruption Budget..."
echo ""

kubectl apply -f "$K8S_DIR/pod-disruption-budget.yaml"
log_success "PDB configured (minAvailable: 2)"

#===============================================================================
# STEP 7: Wait for deployments
#===============================================================================
echo ""
log_step "STEP 7: Waiting for deployments to be ready..."
echo ""

log_info "Waiting for php-apache pods..."
kubectl rollout status deployment/php-apache -n k8s-resilience-experiment --timeout=180s

echo ""
log_success "All deployments are ready!"

#===============================================================================
# STEP 8: Verify setup
#===============================================================================
echo ""
log_step "STEP 8: Verifying experiment setup..."
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

log_info "Testing php-apache service..."
if curl -s --max-time 5 http://localhost:30080 > /dev/null; then
    log_success "php-apache service is responding!"
else
    log_warning "php-apache service not yet responding on NodePort. It may need a moment."
fi
