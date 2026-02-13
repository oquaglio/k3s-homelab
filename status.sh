#!/bin/bash

echo "========================================="
echo "K3s Homelab Status"
echo "========================================="
echo ""

export KUBECONFIG=~/.kube/config

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if K3s is running
if ! systemctl is-active --quiet k3s; then
    echo -e "${RED}❌ K3s is not running${NC}"
    echo "Start it with: sudo systemctl start k3s"
    exit 1
fi

echo -e "${GREEN}✓ K3s is running${NC}"
echo ""

# Cluster info
echo -e "${YELLOW}Cluster Nodes:${NC}"
kubectl get nodes
echo ""

# Get service URLs
echo -e "${YELLOW}Service Access URLs:${NC}"
echo ""

# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# nginx
NGINX_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
if [ ! -z "$NGINX_PORT" ]; then
    echo -e "  ${GREEN}nginx:${NC}       http://$NODE_IP:$NGINX_PORT"
fi

# Portainer
PORTAINER_PORT=$(kubectl get svc portainer -n portainer -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
if [ ! -z "$PORTAINER_PORT" ]; then
    echo -e "  ${GREEN}Portainer:${NC}   http://$NODE_IP:$PORTAINER_PORT"
fi

# Grafana
GRAFANA_PORT=$(kubectl get svc kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
if [ ! -z "$GRAFANA_PORT" ]; then
    echo -e "  ${GREEN}Grafana:${NC}     http://$NODE_IP:$GRAFANA_PORT (admin/admin)"
fi

# Prometheus
PROMETHEUS_PORT=$(kubectl get svc kube-prometheus-stack-prometheus -n monitoring -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
if [ ! -z "$PROMETHEUS_PORT" ]; then
    echo -e "  ${GREEN}Prometheus:${NC}  http://$NODE_IP:$PROMETHEUS_PORT"
fi

echo ""

# Pod status by namespace
echo -e "${YELLOW}Pod Status by Namespace:${NC}"
echo ""

for ns in default monitoring portainer kubernetes-dashboard; do
    POD_COUNT=$(kubectl get pods -n $ns 2>/dev/null | grep -v NAME | wc -l)
    if [ "$POD_COUNT" -gt 0 ]; then
        echo "  Namespace: $ns"
        kubectl get pods -n $ns 2>/dev/null | tail -n +2 | while read line; do
            STATUS=$(echo $line | awk '{print $3}')
            if [ "$STATUS" = "Running" ]; then
                echo -e "    ${GREEN}✓${NC} $line"
            else
                echo -e "    ${YELLOW}⚠${NC} $line"
            fi
        done
        echo ""
    fi
done

# Resource usage
echo -e "${YELLOW}Node Resource Usage:${NC}"
kubectl top nodes 2>/dev/null || echo "  (metrics-server not ready yet)"
echo ""

# Quick stats
echo -e "${YELLOW}Quick Stats:${NC}"
echo "  Total Pods:        $(kubectl get pods --all-namespaces | grep -v NAME | wc -l)"
echo "  Total Services:    $(kubectl get svc --all-namespaces | grep -v NAME | wc -l)"
echo "  Total Deployments: $(kubectl get deployments --all-namespaces | grep -v NAME | wc -l)"
echo ""

echo "========================================="
echo "For Kubernetes Dashboard:"
echo "  1. kubectl proxy"
echo "  2. Visit: http://${K3S_HOSTNAME:-localhost}:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
echo "  3. Token: kubectl -n kubernetes-dashboard create token admin-user"
echo "========================================="
