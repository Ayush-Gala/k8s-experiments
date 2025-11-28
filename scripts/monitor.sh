#!/bin/bash
#===============================================================================
# Kubernetes Resilience Experiment - Real-time Monitoring
#===============================================================================
# Provides real-time visibility into the cluster during the experiment:
# - Pod status and restarts
# - HPA scaling activity
# - Events in the namespace
# - Service endpoints
#===============================================================================

NAMESPACE="k8s-resilience-experiment"
REFRESH_INTERVAL=${1:-5}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear_screen() {
    clear
}

print_header() {
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}    KUBERNETES RESILIENCE EXPERIMENT - LIVE MONITORING${NC}"
    echo -e "${CYAN}    Refresh: every ${REFRESH_INTERVAL}s | Press Ctrl+C to stop${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    echo ""
}

monitor_pods() {
    echo -e "${BLUE}📦 POD STATUS${NC}"
    echo "─────────────────────────────────────────────────────────────────────────────"
    kubectl get pods -n $NAMESPACE -l run=php-apache \
        -o custom-columns=\
'NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp,NODE:.spec.nodeName' \
        2>/dev/null || echo "  No pods found"
    echo ""
}

monitor_hpa() {
    echo -e "${BLUE}📊 HORIZONTAL POD AUTOSCALER${NC}"
    echo "─────────────────────────────────────────────────────────────────────────────"
    kubectl get hpa -n $NAMESPACE \
        -o custom-columns=\
'NAME:.metadata.name,REFERENCE:.spec.scaleTargetRef.name,MIN:.spec.minReplicas,MAX:.spec.maxReplicas,CURRENT:.status.currentReplicas,CPU%:.status.currentMetrics[0].resource.current.averageUtilization' \
        2>/dev/null || echo "  No HPA configured"
    echo ""
}

monitor_deployment() {
    echo -e "${BLUE}🚀 DEPLOYMENT STATUS${NC}"
    echo "─────────────────────────────────────────────────────────────────────────────"
    kubectl get deployment -n $NAMESPACE php-apache \
        -o custom-columns=\
'NAME:.metadata.name,READY:.status.readyReplicas,UP-TO-DATE:.status.updatedReplicas,AVAILABLE:.status.availableReplicas,REPLICAS:.spec.replicas' \
        2>/dev/null || echo "  Deployment not found"
    echo ""
}

monitor_endpoints() {
    echo -e "${BLUE}🌐 SERVICE ENDPOINTS${NC}"
    echo "─────────────────────────────────────────────────────────────────────────────"
    ENDPOINTS=$(kubectl get endpoints php-apache -n $NAMESPACE -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
    if [[ -n "$ENDPOINTS" ]]; then
        echo "  Active endpoints: $ENDPOINTS"
        ENDPOINT_COUNT=$(echo $ENDPOINTS | wc -w)
        echo "  Total endpoints: $ENDPOINT_COUNT"
    else
        echo "  No active endpoints"
    fi
    echo ""
}

monitor_events() {
    echo -e "${BLUE}📋 RECENT EVENTS (last 10)${NC}"
    echo "─────────────────────────────────────────────────────────────────────────────"
    kubectl get events -n $NAMESPACE \
        --sort-by='.lastTimestamp' \
        -o custom-columns=\
'TIME:.lastTimestamp,TYPE:.type,REASON:.reason,OBJECT:.involvedObject.name,MESSAGE:.message' \
        2>/dev/null | tail -11 | head -10 || echo "  No events"
    echo ""
}

monitor_pdb() {
    echo -e "${BLUE}🛡️  POD DISRUPTION BUDGET${NC}"
    echo "─────────────────────────────────────────────────────────────────────────────"
    kubectl get pdb -n $NAMESPACE \
        -o custom-columns=\
'NAME:.metadata.name,MIN-AVAILABLE:.spec.minAvailable,ALLOWED-DISRUPTIONS:.status.disruptionsAllowed,CURRENT:.status.currentHealthy,DESIRED:.status.desiredHealthy' \
        2>/dev/null || echo "  No PDB configured"
    echo ""
}

monitor_locust() {
    echo -e "${BLUE}🦗 LOCUST LOAD GENERATOR${NC}"
    echo "─────────────────────────────────────────────────────────────────────────────"
    kubectl get pods -n $NAMESPACE -l app=locust \
        -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready' \
        2>/dev/null || echo "  Locust not deployed"
    echo ""
}

print_footer() {
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "  Last updated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}===============================================================================${NC}"
}

# Main monitoring loop
while true; do
    clear_screen
    print_header
    monitor_deployment
    monitor_pods
    monitor_hpa
    monitor_pdb
    monitor_endpoints
    monitor_locust
    monitor_events
    print_footer
    
    sleep $REFRESH_INTERVAL
done

