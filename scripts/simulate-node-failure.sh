#!/bin/bash
#===============================================================================
# Kubernetes Resilience Experiment - Node Failure Simulation
#===============================================================================
# Simulates node-level failures to demonstrate Kubernetes self-healing:
# - Node drain (graceful removal for maintenance)
# - Node cordon (prevent new scheduling)
# - Network partition simulation (node becomes unresponsive)
#
# Note: In single-node clusters (like Killercoda), some scenarios may be limited.
# The script adapts based on available nodes.
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $1"
}

show_node_status() {
    echo ""
    log_info "Current node status:"
    kubectl get nodes -o wide
    echo ""
    log_info "Pod distribution across nodes:"
    kubectl get pods -n $NAMESPACE -l run=php-apache -o wide
    echo ""
}

show_pod_status() {
    echo ""
    log_info "Current pod status:"
    kubectl get pods -n $NAMESPACE -l run=php-apache -o wide
    echo ""
}

get_nodes() {
    kubectl get nodes -o jsonpath='{.items[*].metadata.name}'
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
scenario_node_cordon() {
    echo ""
    echo "==============================================================================="
    echo "  SCENARIO 1: Node Cordon (Prevent New Scheduling)"
    echo "==============================================================================="
    echo ""
    log_info "Cordoning a node prevents new pods from being scheduled on it"
    log_info "Existing pods continue running; used before maintenance"
    echo ""
    
    show_node_status
    
    NODES=($(get_nodes))
    NODE_COUNT=${#NODES[@]}
    
    if [[ $NODE_COUNT -lt 1 ]]; then
        log_error "No nodes available"
        return
    fi
    
    # Select the last worker node (avoid control plane if possible)
    TARGET_NODE=${NODES[$((NODE_COUNT-1))]}
    
    log_action "Cordoning node: $TARGET_NODE"
    kubectl cordon $TARGET_NODE
    
    log_success "Node cordoned. New pods cannot be scheduled here."
    show_node_status
    
    log_info "Now let's trigger a pod reschedule by deleting a pod..."
    POD=$(kubectl get pods -n $NAMESPACE -l run=php-apache -o jsonpath='{.items[0].metadata.name}')
    log_action "Deleting pod: $POD"
    kubectl delete pod $POD -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true
    
    sleep 5
    log_info "New pod should be scheduled on remaining uncordoned nodes:"
    show_pod_status
    
    # Uncordon
    log_action "Uncordoning node: $TARGET_NODE"
    kubectl uncordon $TARGET_NODE
    log_success "Node uncordoned and available for scheduling again"
    show_node_status
}

scenario_node_drain() {
    echo ""
    echo "==============================================================================="
    echo "  SCENARIO 2: Node Drain (Graceful Eviction)"
    echo "==============================================================================="
    echo ""
    log_info "Draining a node gracefully evicts all pods to other nodes"
    log_info "Respects PodDisruptionBudgets; used for node maintenance"
    echo ""
    
    show_node_status
    
    NODES=($(get_nodes))
    NODE_COUNT=${#NODES[@]}
    
    if [[ $NODE_COUNT -lt 2 ]]; then
        log_warning "Node drain requires at least 2 nodes for pod migration"
        log_info "In a single-node cluster, we'll simulate by scaling down and up"
        
        log_action "Simulating drain by scaling deployment to 0..."
        kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=0
        
        sleep 5
        show_pod_status
        
        log_action "Simulating recovery by scaling back to 3 replicas..."
        kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=3
        
        wait_for_recovery 60
        show_pod_status
        return
    fi
    
    # Select a worker node (not the control plane)
    TARGET_NODE=${NODES[$((NODE_COUNT-1))]}
    
    log_warning "This will evict all pods from node: $TARGET_NODE"
    read -p "Continue? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Scenario cancelled"
        return
    fi
    
    log_action "Draining node: $TARGET_NODE"
    kubectl drain $TARGET_NODE \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --force \
        --grace-period=10 \
        --timeout=120s || true
    
    log_info "Node drained. Pods should be rescheduled on other nodes."
    show_pod_status
    wait_for_recovery 90
    
    # Uncordon
    log_action "Uncordoning node: $TARGET_NODE"
    kubectl uncordon $TARGET_NODE
    log_success "Node uncordoned and available again"
    show_node_status
}

scenario_node_pressure() {
    echo ""
    echo "==============================================================================="
    echo "  SCENARIO 3: Simulated Node Pressure"
    echo "==============================================================================="
    echo ""
    log_info "Simulating resource pressure on pods (memory/CPU limits)"
    log_info "Kubernetes will restart pods that exceed their limits"
    echo ""
    
    show_pod_status
    
    log_action "Creating a resource-intensive pod to simulate pressure..."
    
    # Create a temporary pod that consumes resources
    kubectl run stress-test \
        -n $NAMESPACE \
        --image=busybox \
        --restart=Never \
        --limits='cpu=200m,memory=128Mi' \
        -- sh -c 'while true; do :; done' 2>/dev/null || true
    
    log_info "Stress pod created. Let it run for 30 seconds..."
    sleep 30
    
    log_action "Cleaning up stress pod..."
    kubectl delete pod stress-test -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true
    
    show_pod_status
    log_success "Resource pressure scenario complete"
}

scenario_pod_eviction() {
    echo ""
    echo "==============================================================================="
    echo "  SCENARIO 4: Kubernetes Pod Eviction"
    echo "==============================================================================="
    echo ""
    log_info "Simulating pod eviction via the Kubernetes Eviction API"
    log_info "This respects PDB and is the preferred way to remove pods"
    echo ""
    
    show_pod_status
    
    POD=$(kubectl get pods -n $NAMESPACE -l run=php-apache -o jsonpath='{.items[0].metadata.name}')
    
    log_action "Evicting pod: $POD via Eviction API"
    
    # Create eviction request
    kubectl create -f - <<EOF
apiVersion: policy/v1
kind: Eviction
metadata:
  name: $POD
  namespace: $NAMESPACE
EOF
    
    log_info "Eviction request sent. Pod should be replaced."
    sleep 5
    
    wait_for_recovery 60
    show_pod_status
}

scenario_taint_node() {
    echo ""
    echo "==============================================================================="
    echo "  SCENARIO 5: Node Taint (NoSchedule/NoExecute)"
    echo "==============================================================================="
    echo ""
    log_info "Tainting a node prevents pods without tolerations from running"
    log_info "NoExecute taint evicts existing pods immediately"
    echo ""
    
    show_node_status
    
    NODES=($(get_nodes))
    TARGET_NODE=${NODES[0]}
    
    log_warning "Adding NoSchedule taint to node: $TARGET_NODE"
    kubectl taint nodes $TARGET_NODE experiment=failure:NoSchedule --overwrite || true
    
    log_info "Taint added. New pods without toleration won't schedule here."
    kubectl describe node $TARGET_NODE | grep -A5 "Taints:"
    echo ""
    
    # Trigger reschedule
    POD=$(kubectl get pods -n $NAMESPACE -l run=php-apache -o jsonpath='{.items[0].metadata.name}')
    log_action "Deleting pod to observe scheduling behavior: $POD"
    kubectl delete pod $POD -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true
    
    sleep 5
    show_pod_status
    
    # Remove taint
    log_action "Removing taint from node: $TARGET_NODE"
    kubectl taint nodes $TARGET_NODE experiment=failure:NoSchedule- || true
    log_success "Taint removed"
    
    wait_for_recovery 60
    show_pod_status
}

# Menu
show_menu() {
    echo ""
    echo "==============================================================================="
    echo "    KUBERNETES NODE FAILURE SIMULATION"
    echo "==============================================================================="
    echo ""
    echo "Select a failure scenario to execute:"
    echo ""
    echo "  1) Node Cordon        - Prevent new pod scheduling on a node"
    echo "  2) Node Drain         - Gracefully evict all pods from a node"
    echo "  3) Resource Pressure  - Simulate node resource pressure"
    echo "  4) Pod Eviction       - Evict pod via Eviction API (respects PDB)"
    echo "  5) Node Taint         - Add taint to prevent scheduling"
    echo "  6) Show Node Status   - Display node and pod distribution"
    echo "  7) Exit"
    echo ""
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice (1-7): " choice
    
    case $choice in
        1) scenario_node_cordon ;;
        2) scenario_node_drain ;;
        3) scenario_node_pressure ;;
        4) scenario_pod_eviction ;;
        5) scenario_taint_node ;;
        6) show_node_status ;;
        7) echo "Exiting..."; exit 0 ;;
        *) log_warning "Invalid choice. Please enter 1-7." ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
done

