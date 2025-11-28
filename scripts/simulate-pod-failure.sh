#!/bin/bash
#===============================================================================
# Kubernetes Resilience Experiment - Pod Failure Simulation
#===============================================================================
# Simulates pod failures to demonstrate Kubernetes self-healing:
# - Single pod deletion (simulates container crash)
# - Multiple pod deletion (simulates widespread failure)
# - Random pod killing (chaos engineering style)
#
# Kubernetes should automatically restart/replace failed pods while
# maintaining service availability.
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

NAMESPACE="k8s-resilience-experiment"
DEPLOYMENT="php-apache"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $1"
}

log_action() {
    echo -e "${CYAN}[ACTION]${NC} $(date '+%H:%M:%S') $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%H:%M:%S') $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%H:%M:%S') $1"
}

show_pod_status() {
    echo ""
    log_info "Current pod status:"
    kubectl get pods -n $NAMESPACE -l run=php-apache -o wide
    echo ""
}

wait_for_recovery() {
    local timeout=${1:-60}
    log_info "Waiting up to ${timeout}s for recovery..."
    
    local start_time=$(date +%s)
    while true; do
        local ready_pods=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired_pods=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.replicas}')
        
        if [[ "$ready_pods" == "$desired_pods" ]]; then
            log_success "Recovery complete: $ready_pods/$desired_pods pods ready"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $timeout ]]; then
            log_warning "Timeout reached. Current status: $ready_pods/$desired_pods pods ready"
            return 1
        fi
        
        echo -ne "\r  Recovering... $ready_pods/$desired_pods pods ready (${elapsed}s elapsed)"
        sleep 2
    done
}

# Scenario functions
scenario_single_pod_failure() {
    echo ""
    echo "==============================================================================="
    echo "  SCENARIO 1: Single Pod Failure"
    echo "==============================================================================="
    echo ""
    log_info "This simulates a single container crash or OOM kill"
    log_info "Kubernetes should immediately schedule a replacement pod"
    echo ""
    
    show_pod_status
    
    # Get a random pod name
    POD=$(kubectl get pods -n $NAMESPACE -l run=php-apache -o jsonpath='{.items[0].metadata.name}')
    
    log_action "Deleting pod: $POD"
    kubectl delete pod $POD -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true
    
    log_info "Pod deleted. Kubernetes should restart it automatically."
    echo ""
    
    # Watch recovery
    wait_for_recovery 60
    show_pod_status
}

scenario_multiple_pod_failure() {
    echo ""
    echo "==============================================================================="
    echo "  SCENARIO 2: Multiple Pod Failure (50% of replicas)"
    echo "==============================================================================="
    echo ""
    log_info "This simulates a partial cluster failure or network partition"
    log_info "PDB ensures minimum availability; Kubernetes replaces all failed pods"
    echo ""
    
    show_pod_status
    
    # Get half of the pods
    TOTAL_PODS=$(kubectl get pods -n $NAMESPACE -l run=php-apache --no-headers | wc -l)
    PODS_TO_KILL=$((TOTAL_PODS / 2))
    
    if [[ $PODS_TO_KILL -lt 1 ]]; then
        PODS_TO_KILL=1
    fi
    
    log_action "Deleting $PODS_TO_KILL of $TOTAL_PODS pods..."
    
    PODS=$(kubectl get pods -n $NAMESPACE -l run=php-apache -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | head -n $PODS_TO_KILL)
    
    for POD in $PODS; do
        log_action "Deleting pod: $POD"
        kubectl delete pod $POD -n $NAMESPACE --grace-period=0 --force 2>/dev/null &
    done
    wait
    
    log_info "Multiple pods deleted. Observing recovery..."
    echo ""
    
    wait_for_recovery 90
    show_pod_status
}

scenario_rolling_failures() {
    echo ""
    echo "==============================================================================="
    echo "  SCENARIO 3: Rolling Failures (Chaos Engineering)"
    echo "==============================================================================="
    echo ""
    log_info "This simulates intermittent failures over time"
    log_info "Pods fail randomly while load continues; tests sustained resilience"
    echo ""
    
    show_pod_status
    
    log_action "Starting rolling failure simulation (5 cycles, 10s apart)..."
    echo ""
    
    for i in {1..5}; do
        # Get a random pod
        PODS=($(kubectl get pods -n $NAMESPACE -l run=php-apache -o jsonpath='{.items[*].metadata.name}'))
        if [[ ${#PODS[@]} -gt 0 ]]; then
            RANDOM_INDEX=$((RANDOM % ${#PODS[@]}))
            POD=${PODS[$RANDOM_INDEX]}
            
            log_action "Cycle $i/5: Killing pod $POD"
            kubectl delete pod $POD -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true
        fi
        
        if [[ $i -lt 5 ]]; then
            log_info "Waiting 10 seconds before next failure..."
            sleep 10
        fi
    done
    
    echo ""
    log_info "Rolling failures complete. Final recovery status:"
    wait_for_recovery 60
    show_pod_status
}

scenario_all_pods_failure() {
    echo ""
    echo "==============================================================================="
    echo "  SCENARIO 4: Complete Service Failure"
    echo "==============================================================================="
    echo ""
    log_warning "This simulates a catastrophic failure - ALL pods are killed"
    log_info "Service will be briefly unavailable; Kubernetes will recreate all pods"
    echo ""
    
    show_pod_status
    
    read -p "This will cause brief service unavailability. Continue? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Scenario cancelled"
        return
    fi
    
    log_action "Deleting ALL php-apache pods..."
    kubectl delete pods -n $NAMESPACE -l run=php-apache --grace-period=0 --force 2>/dev/null || true
    
    log_info "All pods deleted. Kubernetes will recreate them from the deployment."
    echo ""
    
    wait_for_recovery 120
    show_pod_status
}

# Menu
show_menu() {
    echo ""
    echo "==============================================================================="
    echo "    KUBERNETES POD FAILURE SIMULATION"
    echo "==============================================================================="
    echo ""
    echo "Select a failure scenario to execute:"
    echo ""
    echo "  1) Single Pod Failure     - Kill one pod (simulates container crash)"
    echo "  2) Multiple Pod Failure   - Kill 50% of pods (simulates partial failure)"
    echo "  3) Rolling Failures       - Random kills over time (chaos engineering)"
    echo "  4) Complete Failure       - Kill ALL pods (catastrophic scenario)"
    echo "  5) Show Current Status    - Display pod and deployment status"
    echo "  6) Exit"
    echo ""
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice (1-6): " choice
    
    case $choice in
        1) scenario_single_pod_failure ;;
        2) scenario_multiple_pod_failure ;;
        3) scenario_rolling_failures ;;
        4) scenario_all_pods_failure ;;
        5) show_pod_status
           kubectl get hpa -n $NAMESPACE
           kubectl get deployment $DEPLOYMENT -n $NAMESPACE ;;
        6) echo "Exiting..."; exit 0 ;;
        *) log_warning "Invalid choice. Please enter 1-6." ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
done

