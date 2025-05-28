#!/bin/bash

# Define color codes for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define the observability namespace
OBSERVABILITY_NAMESPACE="observability"

# Customer namespaces
CUSTOMER_NAMESPACES=("ns-52327214" "ns-48414609" "ns-94714545")

# Update the service name for trouble-box
TROUBLE_BOX_SERVICE_NAME="trouble-box"

# Turn off debug mode completely
DEBUG_MODE=false

# Function to check if a port is available - FIX THE LOGIC
check_port_available() {
    local port=$1
    if command -v nc >/dev/null 2>&1; then
        # If nc returns success (0), port is in use (not available)
        nc -z localhost $port >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            return 1  # Port is NOT available
        else
            return 0  # Port is available
        fi
    elif command -v lsof >/dev/null 2>&1; then
        # If lsof returns success (0), port is in use (not available)
        lsof -i :$port >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            return 1  # Port is NOT available
        else
            return 0  # Port is available
        fi
    else
        # If neither nc nor lsof are available, assume port is available
        return 0
    fi
}

# Function to clean up all kubectl port-forward processes
clean_all_port_forwards() {
    echo -e "${BLUE}Cleaning up all port forwarding processes...${NC}"
    
    # Kill all kubectl port-forward processes
    pkill -f "kubectl port-forward" 2>/dev/null || true
    
    # Remove the temporary file if it exists
    rm -f /tmp/port-forward-pids 2>/dev/null || true
    
    echo -e "${GREEN}All port forwards cleaned up${NC}"
}

# Print header
echo -e "${BLUE}================================${NC}"
echo -e "${GREEN} Port Forward Service Access${NC}"
echo -e "${BLUE}================================${NC}"

# Clean up any existing port forwards before starting
clean_all_port_forwards

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

echo -e "${BLUE}Starting port forwarding for all services...${NC}"

# Function to start port forwarding in background
start_port_forward() {
    local namespace=$1
    local service=$2
    local local_port=$3
    local remote_port=$4
    local service_name=$5
    
    # Add some debugging
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${BLUE}DEBUG: Attempting to forward $namespace/$service on port $local_port:$remote_port${NC}"
    fi
    
    # Check if port is already in use
    if ! check_port_available $local_port; then
        echo -e "${YELLOW}Port $local_port is already in use. Skipping port forward for $service_name.${NC}"
        return 1
    fi
    
    # Check if service exists
    if ! kubectl get svc -n $namespace $service &> /dev/null; then
        echo -e "${YELLOW}Service $service in namespace $namespace not found. Skipping.${NC}"
        
        # Debug service info
        if [ "$DEBUG_MODE" = true ]; then
            echo -e "${BLUE}DEBUG: Listing services in namespace $namespace:${NC}"
            kubectl get svc -n $namespace
        fi
        return 1
    fi
    
    # Start port forwarding with debug output
    echo -e "${GREEN}Starting port forward for $service_name...${NC}"
    if [ "$DEBUG_MODE" = true ]; then
        # Run with output visible for debugging
        kubectl port-forward -n $namespace svc/$service $local_port:$remote_port &
    else
        kubectl port-forward -n $namespace svc/$service $local_port:$remote_port &>/dev/null &
    fi
    
    # Save PID for cleanup
    echo $! >> /tmp/port-forward-pids
    
    # Check if port forwarding was successful - FIXED LOGIC
    sleep 2
    if ! check_port_available $local_port; then
        echo -e "${GREEN}✅ Port forward for $service_name running on http://localhost:$local_port${NC}"
    else
        echo -e "${RED}❌ Failed to start port forward for $service_name${NC}"
        # Additional debug info
        if [ "$DEBUG_MODE" = true ]; then
            echo -e "${BLUE}DEBUG: Service endpoints for $namespace/$service:${NC}"
            kubectl get endpoints -n $namespace $service -o yaml
        fi
    fi
}

# Create a file to store PIDs for cleanup
rm -f /tmp/port-forward-pids
touch /tmp/port-forward-pids

# Port forward observability services
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}Forwarding observability services...${NC}"
echo -e "${BLUE}===========================================${NC}"

# Grafana
start_port_forward $OBSERVABILITY_NAMESPACE "grafana" 3000 80 "Grafana"

# Get Grafana credentials
GRAFANA_USER=$(kubectl get secret --namespace $OBSERVABILITY_NAMESPACE grafana -o jsonpath="{.data.admin-user}" | base64 --decode 2>/dev/null)
GRAFANA_PASS=$(kubectl get secret --namespace $OBSERVABILITY_NAMESPACE grafana -o jsonpath="{.data.admin-password}" | base64 --decode 2>/dev/null)

if [ ! -z "$GRAFANA_USER" ] && [ ! -z "$GRAFANA_PASS" ]; then
    echo -e "${GREEN}Grafana credentials: Username: $GRAFANA_USER / Password: $GRAFANA_PASS${NC}"
fi

# Victoria Metrics
start_port_forward $OBSERVABILITY_NAMESPACE "vmsingle-victoria-metrics-single-server" 8428 8428 "Victoria Metrics"

# VMAgent
start_port_forward $OBSERVABILITY_NAMESPACE "vmagent" 8429 8429 "Victoria Metrics Agent"

# VMAlert
start_port_forward $OBSERVABILITY_NAMESPACE "vmalert-victoria-metrics-alert-server" 8880 8880 "Victoria Metrics Alert"

# Alertmanager
start_port_forward $OBSERVABILITY_NAMESPACE "alertmanager" 9093 9093 "Alertmanager"

# Loki (if available)
start_port_forward $OBSERVABILITY_NAMESPACE "loki" 3100 3100 "Loki"

# Port forward trouble-box services for each customer namespace
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}Forwarding Trouble-Box applications...${NC}"
echo -e "${BLUE}===========================================${NC}"

# Set up separate ports for each trouble-box instance
TB_LOCAL_PORTS=(8000 8001 8002)

# Create a simple counter
count=0

# Silently clear any existing port-forwards for trouble-box
pkill -f "kubectl port-forward.*trouble-box" 2>/dev/null || true

for ns in "${CUSTOMER_NAMESPACES[@]}"; do
    local_port=${TB_LOCAL_PORTS[$count]}
    
    # Get endpoint IP to verify the service has a target
    ENDPOINT_IP=$(kubectl get endpoints -n $ns trouble-box -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
    
    if [ -z "$ENDPOINT_IP" ]; then
        echo -e "${YELLOW}⚠️ Trouble-Box in namespace $ns appears to have no endpoints. Service may not work.${NC}"
    fi
    
    # Run port-forward quietly in the background
    echo -e "${GREEN}Starting port forward for Trouble-Box ($ns)...${NC}"
    
    # Enable debug for one run to see what's happening
    echo -e "${BLUE}DEBUG: Running kubectl port-forward -n $ns svc/trouble-box $local_port:80${NC}"
    kubectl port-forward -n $ns svc/trouble-box $local_port:80 &
    
    # Store PID for cleanup
    PID=$!
    echo $PID >> /tmp/port-forward-pids
    
    # Brief pause
    sleep 3
    
    # Verify port forward is working - FIXED LOGIC
    if ! check_port_available $local_port; then
        echo -e "${GREEN}✅ Trouble-Box ($ns): http://localhost:$local_port${NC}"
    else
        echo -e "${RED}❌ Could not set up port forwarding for Trouble-Box ($ns)${NC}"
        
        # Additional troubleshooting
        echo -e "${BLUE}Troubleshooting Trouble-Box service in $ns:${NC}"
        kubectl get pods -n $ns -l app=trouble-box
        kubectl describe svc -n $ns trouble-box | grep -E "Name:|Selector:|Type:|IP:|Port:|TargetPort:|Endpoints:"
        
        kill $PID 2>/dev/null || true
    fi
    
    ((count++))
done

# Print summary
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}Port forwarding is active for the following services:${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}Grafana:       http://localhost:3000${NC}"
echo -e "${GREEN}VictoriaMetrics: http://localhost:8428${NC}"
echo -e "${GREEN}VMAgent:       http://localhost:8429${NC}"
echo -e "${GREEN}VMAlert:       http://localhost:8880${NC}"
echo -e "${GREEN}Alertmanager:  http://localhost:9093${NC}"
echo -e "${GREEN}Loki:          http://localhost:3100 (if available)${NC}"

local_port=8000
for ns in "${CUSTOMER_NAMESPACES[@]}"; do
    echo -e "${GREEN}Trouble-Box ($ns): http://localhost:$local_port${NC}"
    ((local_port++))
done

echo -e "${BLUE}===========================================${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop all port-forwarding${NC}"
echo -e "${BLUE}===========================================${NC}"

# Trap Ctrl+C and cleanup
cleanup() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${GREEN}Stopping all port forwarding...${NC}"
    
    clean_all_port_forwards
    
    echo -e "${BLUE}===========================================${NC}"
    exit 0
}

# Trap more signals for better cleanup
trap cleanup INT TERM EXIT

# Keep the script running
while true; do
    sleep 1
done
