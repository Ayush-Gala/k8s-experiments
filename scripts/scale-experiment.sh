#!/bin/bash
#===============================================================================
# Kubernetes Resilience Experiment - Scale Configuration
#===============================================================================
# Configures the experiment for different scale levels:
#   - small:  Up to 100 users   (default, works on Killercoda)
#   - medium: Up to 1,000 users (requires multi-node cluster)
#   - large:  Up to 10,000 users (requires production cluster)
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

show_current_scale() {
    echo ""
    log_info "Current Scale Configuration:"
    echo ""
    
    # Get php-apache replicas
    CURRENT_REPLICAS=$(kubectl get deployment php-apache -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "N/A")
    HPA_MIN=$(kubectl get hpa php-apache-hpa -n $NAMESPACE -o jsonpath='{.spec.minReplicas}' 2>/dev/null || echo "N/A")
    HPA_MAX=$(kubectl get hpa php-apache-hpa -n $NAMESPACE -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo "N/A")
    LOCUST_WORKERS=$(kubectl get deployment locust-worker -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "N/A")
    
    echo "  php-apache replicas:    $CURRENT_REPLICAS"
    echo "  HPA min/max replicas:   $HPA_MIN / $HPA_MAX"
    echo "  Locust workers:         $LOCUST_WORKERS"
    echo ""
    
    # Calculate approximate capacity
    if [[ "$HPA_MAX" != "N/A" && "$LOCUST_WORKERS" != "N/A" ]]; then
        APPROX_CAPACITY=$((LOCUST_WORKERS * 1000))
        echo "  Approximate user capacity: ~${APPROX_CAPACITY} users"
    fi
    echo ""
}

scale_small() {
    echo ""
    echo "==============================================================================="
    echo "  CONFIGURING: SMALL SCALE (up to 100 users)"
    echo "==============================================================================="
    echo ""
    log_info "This configuration works on Killercoda and small clusters"
    echo ""
    
    log_info "Scaling php-apache deployment..."
    kubectl scale deployment php-apache -n $NAMESPACE --replicas=3
    
    log_info "Updating HPA limits..."
    kubectl patch hpa php-apache-hpa -n $NAMESPACE --type='json' \
        -p='[{"op": "replace", "path": "/spec/minReplicas", "value": 3},
             {"op": "replace", "path": "/spec/maxReplicas", "value": 10}]'
    
    log_info "Scaling Locust workers..."
    kubectl scale deployment locust-worker -n $NAMESPACE --replicas=2
    
    log_success "Small scale configuration applied!"
    echo ""
    echo "Recommended Locust settings:"
    echo "  - Number of users: 50-100"
    echo "  - Spawn rate: 10"
    echo ""
}

scale_medium() {
    echo ""
    echo "==============================================================================="
    echo "  CONFIGURING: MEDIUM SCALE (up to 1,000 users)"
    echo "==============================================================================="
    echo ""
    log_warning "This requires a multi-node cluster with adequate resources"
    echo ""
    
    # Check node count
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    if [[ $NODE_COUNT -lt 2 ]]; then
        log_warning "Only $NODE_COUNT node(s) detected. Medium scale works best with 2+ nodes."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    log_info "Scaling php-apache deployment..."
    kubectl scale deployment php-apache -n $NAMESPACE --replicas=5
    
    log_info "Updating HPA limits..."
    kubectl patch hpa php-apache-hpa -n $NAMESPACE --type='json' \
        -p='[{"op": "replace", "path": "/spec/minReplicas", "value": 5},
             {"op": "replace", "path": "/spec/maxReplicas", "value": 30}]'
    
    log_info "Scaling Locust workers..."
    kubectl scale deployment locust-worker -n $NAMESPACE --replicas=5
    
    log_info "Updating PDB for higher availability..."
    kubectl patch pdb php-apache-pdb -n $NAMESPACE --type='json' \
        -p='[{"op": "replace", "path": "/spec/minAvailable", "value": 3}]'
    
    log_success "Medium scale configuration applied!"
    echo ""
    echo "Recommended Locust settings:"
    echo "  - Number of users: 500-1000"
    echo "  - Spawn rate: 50"
    echo ""
}

scale_large() {
    echo ""
    echo "==============================================================================="
    echo "  CONFIGURING: LARGE SCALE (up to 10,000 users)"
    echo "==============================================================================="
    echo ""
    log_warning "This requires a production-grade cluster with significant resources!"
    echo ""
    echo "Prerequisites:"
    echo "  - 3+ nodes with at least 4 CPU cores each"
    echo "  - Adequate memory (16GB+ per node recommended)"
    echo "  - Fast network interconnect"
    echo ""
    
    # Check node count and resources
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    if [[ $NODE_COUNT -lt 3 ]]; then
        log_warning "Only $NODE_COUNT node(s) detected. Large scale requires 3+ nodes."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    log_info "Scaling php-apache deployment..."
    kubectl scale deployment php-apache -n $NAMESPACE --replicas=10
    
    log_info "Updating HPA limits..."
    kubectl patch hpa php-apache-hpa -n $NAMESPACE --type='json' \
        -p='[{"op": "replace", "path": "/spec/minReplicas", "value": 10},
             {"op": "replace", "path": "/spec/maxReplicas", "value": 100}]'
    
    log_info "Scaling Locust workers..."
    kubectl scale deployment locust-worker -n $NAMESPACE --replicas=15
    
    log_info "Updating PDB for higher availability..."
    kubectl patch pdb php-apache-pdb -n $NAMESPACE --type='json' \
        -p='[{"op": "replace", "path": "/spec/minAvailable", "value": 5}]'
    
    log_success "Large scale configuration applied!"
    echo ""
    echo "Recommended Locust settings:"
    echo "  - Number of users: 5000-10000"
    echo "  - Spawn rate: 100-500"
    echo ""
    log_warning "Monitor cluster resources carefully during large-scale tests!"
    echo ""
}

custom_scale() {
    echo ""
    echo "==============================================================================="
    echo "  CUSTOM SCALE CONFIGURATION"
    echo "==============================================================================="
    echo ""
    
    read -p "Enter target number of users: " TARGET_USERS
    
    if ! [[ "$TARGET_USERS" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid input. Please enter a number."
        return
    fi
    
    # Calculate recommended settings
    # Rule of thumb: 1 pod per 100 users, 1 Locust worker per 1000 users
    RECOMMENDED_PODS=$((TARGET_USERS / 100))
    if [[ $RECOMMENDED_PODS -lt 3 ]]; then RECOMMENDED_PODS=3; fi
    
    RECOMMENDED_MAX_PODS=$((RECOMMENDED_PODS * 3))
    if [[ $RECOMMENDED_MAX_PODS -lt 10 ]]; then RECOMMENDED_MAX_PODS=10; fi
    
    RECOMMENDED_WORKERS=$((TARGET_USERS / 1000))
    if [[ $RECOMMENDED_WORKERS -lt 2 ]]; then RECOMMENDED_WORKERS=2; fi
    
    RECOMMENDED_PDB=$((RECOMMENDED_PODS / 2))
    if [[ $RECOMMENDED_PDB -lt 2 ]]; then RECOMMENDED_PDB=2; fi
    
    echo ""
    echo "Recommended configuration for $TARGET_USERS users:"
    echo "  - php-apache min replicas: $RECOMMENDED_PODS"
    echo "  - php-apache max replicas: $RECOMMENDED_MAX_PODS"
    echo "  - Locust workers:          $RECOMMENDED_WORKERS"
    echo "  - PDB minAvailable:        $RECOMMENDED_PDB"
    echo ""
    
    read -p "Apply these settings? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Configuration cancelled"
        return
    fi
    
    log_info "Applying custom configuration..."
    
    kubectl scale deployment php-apache -n $NAMESPACE --replicas=$RECOMMENDED_PODS
    
    kubectl patch hpa php-apache-hpa -n $NAMESPACE --type='json' \
        -p="[{\"op\": \"replace\", \"path\": \"/spec/minReplicas\", \"value\": $RECOMMENDED_PODS},
             {\"op\": \"replace\", \"path\": \"/spec/maxReplicas\", \"value\": $RECOMMENDED_MAX_PODS}]"
    
    kubectl scale deployment locust-worker -n $NAMESPACE --replicas=$RECOMMENDED_WORKERS
    
    kubectl patch pdb php-apache-pdb -n $NAMESPACE --type='json' \
        -p="[{\"op\": \"replace\", \"path\": \"/spec/minAvailable\", \"value\": $RECOMMENDED_PDB}]"
    
    log_success "Custom configuration applied for $TARGET_USERS users!"
    echo ""
}

# Menu
show_menu() {
    echo ""
    echo "==============================================================================="
    echo "    KUBERNETES RESILIENCE EXPERIMENT - SCALE CONFIGURATION"
    echo "==============================================================================="
    echo ""
    echo "Select a scale profile:"
    echo ""
    echo "  1) Small   - Up to 100 users    (Killercoda compatible)"
    echo "  2) Medium  - Up to 1,000 users  (multi-node cluster)"
    echo "  3) Large   - Up to 10,000 users (production cluster)"
    echo "  4) Custom  - Specify your target user count"
    echo "  5) Show Current Configuration"
    echo "  6) Exit"
    echo ""
}

# Main
while true; do
    show_menu
    read -p "Enter your choice (1-6): " choice
    
    case $choice in
        1) scale_small ;;
        2) scale_medium ;;
        3) scale_large ;;
        4) custom_scale ;;
        5) show_current_scale ;;
        6) echo "Exiting..."; exit 0 ;;
        *) log_warning "Invalid choice. Please enter 1-6." ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
done

