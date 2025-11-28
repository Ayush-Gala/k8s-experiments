#!/bin/bash
#===============================================================================
# Kubernetes Resilience Experiment - Start Locust Load Generator
#===============================================================================
# Starts Locust locally, pointing to the php-apache NodePort service
#===============================================================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo ""
echo "==============================================================================="
echo "    STARTING LOCUST LOAD GENERATOR"
echo "==============================================================================="
echo ""

# Check if locust is installed
if ! command -v locust &> /dev/null; then
    echo -e "${YELLOW}[WARNING]${NC} Locust not found. Installing..."
    apt-get update -qq && apt-get install -y -qq python3-locust
fi

# Verify php-apache is accessible
echo -e "${BLUE}[INFO]${NC} Testing connection to php-apache service..."
if curl -s --max-time 5 http://localhost:30080 > /dev/null; then
    echo -e "${GREEN}[SUCCESS]${NC} php-apache service is responding!"
else
    echo -e "${YELLOW}[WARNING]${NC} php-apache not responding yet. Locust will retry."
fi

echo ""
echo "==============================================================================="
echo "    LOCUST WEB UI"
echo "==============================================================================="
echo ""
echo "Access the Locust UI:"
echo "  - In Killercoda: Traffic/Ports → Enter port 8089 → Click Access"
echo ""
echo "Recommended test settings:"
echo "  - Number of users: 50"
echo "  - Spawn rate: 10"
echo ""
echo "Press Ctrl+C to stop Locust"
echo ""
echo "==============================================================================="
echo ""

# Start Locust
cd "$PROJECT_DIR"
locust -f locust/locustfile.py --host=http://localhost:30080

