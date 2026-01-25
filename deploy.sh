#!/bin/bash
set -e

echo "========================================="
echo "K3s Homelab Deployment Script"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

export KUBECONFIG=~/.kube/config

echo -e "${YELLOW}Deploying applications to K3s cluster...${NC}"
echo ""

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to K3s cluster${NC}"
    echo "Run ./bootstrap.sh first or check if K3s is running: sudo systemctl status k3s"
    exit 1
fi

# Check if secrets have been created
echo -e "${YELLOW}Checking for required secrets...${NC}"
if ! kubectl get secret portainer-admin-password -n portainer &> /dev/null; then
    echo -e "${RED}Error: Portainer admin password secret not found${NC}"
    echo "Run ./secrets.sh first to create required secrets"
    exit 1
fi
echo -e "${GREEN}✓ Required secrets found${NC}"
echo ""

echo -e "${YELLOW}Step 1: Deploying nginx...${NC}"
kubectl apply -f apps/nginx/deployment.yaml
echo -e "${GREEN}✓ nginx deployed${NC}"
echo ""

echo -e "${YELLOW}Step 2: Deploying Portainer...${NC}"
kubectl apply -f monitoring/portainer/portainer.yaml
echo "Waiting for Portainer to be ready..."
# Wait for deployment to exist first
kubectl wait --for=jsonpath='{.status.replicas}'=1 deployment/portainer -n portainer --timeout=60s 2>/dev/null || sleep 10
# Then wait for pods
kubectl wait --for=condition=ready pod -l app=portainer -n portainer --timeout=120s 2>/dev/null || true
echo -e "${GREEN}✓ Portainer deployed${NC}"
echo ""

echo -e "${YELLOW}Step 3: Deploying Kubernetes Dashboard...${NC}"
kubectl apply -f monitoring/kubernetes-dashboard/dashboard.yaml
kubectl apply -f monitoring/kubernetes-dashboard/admin-user.yaml
echo "Waiting for Dashboard to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=kubernetes-dashboard -n kubernetes-dashboard --timeout=120s || true
echo -e "${GREEN}✓ Kubernetes Dashboard deployed${NC}"
echo ""

echo -e "${YELLOW}Step 4: Deploying Kube Prometheus Stack (Grafana + Prometheus)...${NC}"
echo "This may take a few minutes..."
kubectl apply -f monitoring/kube-prometheus-stack/manifests.yaml
echo "Waiting for Grafana to be ready..."
# Delete the test pod if it exists (it's not needed)
kubectl delete pod kube-prometheus-stack-grafana-test -n monitoring 2>/dev/null || true
# Wait for the deployment
kubectl wait --for=condition=available deployment/kube-prometheus-stack-grafana -n monitoring --timeout=300s || true
echo -e "${GREEN}✓ Kube Prometheus Stack deployed${NC}"
echo ""

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Deployment complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Your applications are deployed. Check status with:"
echo "  kubectl get pods --all-namespaces"
echo ""
echo "Access your services:"
echo ""
echo "Getting service ports..."
NGINX_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
PORTAINER_PORT=$(kubectl get svc portainer -n portainer -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
GRAFANA_PORT=$(kubectl get svc kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
PROMETHEUS_PORT=$(kubectl get svc kube-prometheus-stack-prometheus -n monitoring -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")

echo "  • nginx:       http://localhost:${NGINX_PORT}"
echo "  • Portainer:   http://localhost:${PORTAINER_PORT}"
echo "  • Grafana:     http://localhost:${GRAFANA_PORT} (admin/admin)"
echo "  • Prometheus:  http://localhost:${PROMETHEUS_PORT}"
echo ""
echo "For Kubernetes Dashboard:"
echo "  1. Run: kubectl proxy"
echo "  2. Visit: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
echo "  3. Get token: kubectl -n kubernetes-dashboard create token admin-user"