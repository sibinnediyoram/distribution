#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Starting Lightweight Vikunja Monitor...${NC}"
echo "Press [CTRL+C] to stop."

while true; do
    clear
    echo "========================================================"
    echo "   VIKUNJA APP HEALTH MONITOR   $(date)"
    echo "========================================================"

    # 1. Check Pod Status
    echo -e "\n${GREEN}[POD STATUS]${NC}"
    kubectl get pods -n vikunja -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount | head -n 5

    # 2. Check Database Connectivity
    echo -e "\n${GREEN}[INFRASTRUCTURE HEALTH]${NC}"
    PG_STATUS=$(kubectl get pod -n vikunja -l app.kubernetes.io/name=postgresql -o jsonpath="{.items[0].status.phase}")
    if [ "$PG_STATUS" == "Running" ]; then
        echo -e "Postgres: ${GREEN}UP${NC}"
    else
        echo -e "Postgres: ${RED}DOWN${NC}"
    fi


    # 3. Check Application Endpoint (Simulated Load Balancer Check)
    echo -e "\n${GREEN}[ENDPOINT CHECK]${NC}"
    # Note: In Kind, localhost maps to the Ingress Controller
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://vikunja.local/health)

    if [ "$HTTP_CODE" == "200" ]; then
        echo -e "Vikunja Health Endpoint: ${GREEN}200 OK${NC}"
    else
        echo -e "Vikunja Health Endpoint: ${RED}ERROR ($HTTP_CODE)${NC}"
    fi

    # 4. Resource Usage (Requires Metrics Server)
    echo -e "\n${GREEN}[RESOURCE USAGE]${NC}"
    if kubectl top pod -n vikunja &> /dev/null; then
        kubectl top pod -n vikunja --containers
    else
        echo "Metrics API not available (install metrics-server to view)."
    fi

    sleep 5
done