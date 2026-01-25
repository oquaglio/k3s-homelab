#!/bin/bash
set -e

echo "========================================="
echo "K3s Homelab Setup Script"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

export KUBECONFIG=~/.kube/config

echo -e "${YELLOW}Step 1: Verifying K3s installation...${NC}"

# Check if K3s is running
if ! systemctl is-active --quiet k3s; then
    echo -e "${RED}Error: K3s is not running${NC}"
    echo "Start it with: sudo systemctl start k3s"
    echo "Or run ./install.sh to install K3s"
    exit 1
fi

echo -e "${GREEN}✓ K3s is running${NC}"

# Verify kubectl can connect
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to K3s cluster${NC}"
    echo "Check kubeconfig: echo \$KUBECONFIG"
    exit 1
fi

echo -e "${GREEN}✓ kubectl is configured${NC}"

# Show nodes
echo ""
kubectl get nodes
echo ""

echo -e "${YELLOW}Step 2: Creating namespaces...${NC}"

# Apply monitoring namespace (for kube-prometheus-stack)
if [ -f "monitoring/kube-prometheus-stack/namespace.yaml" ]; then
    kubectl apply -f monitoring/kube-prometheus-stack/namespace.yaml
    echo -e "${GREEN}✓ Monitoring namespace created${NC}"
else
    echo -e "${RED}Error: monitoring/kube-prometheus-stack/namespace.yaml not found${NC}"
    exit 1
fi

# Apply portainer namespace
if [ -f "monitoring/portainer/namespace.yaml" ]; then
    kubectl apply -f monitoring/portainer/namespace.yaml
    echo -e "${GREEN}✓ Portainer namespace created${NC}"
else
    echo -e "${RED}Error: monitoring/portainer/namespace.yaml not found${NC}"
    exit 1
fi

# Apply kubernetes-dashboard namespace
if [ -f "monitoring/kubernetes-dashboard/namespace.yaml" ]; then
    kubectl apply -f monitoring/kubernetes-dashboard/namespace.yaml
    echo -e "${GREEN}✓ Kubernetes Dashboard namespace created${NC}"
else
    echo -e "${RED}Error: monitoring/kubernetes-dashboard/namespace.yaml not found${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Setup complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Your cluster is ready for deployments."
echo ""
echo "Next steps:"
echo "1. Create your secrets: cp secrets.sh.example secrets.sh && vi secrets.sh"
echo "2. Run secrets script: ./secrets.sh"
echo "3. Deploy applications: ./deploy.sh"
echo ""
echo "For remote access:"
echo "  ./generate-remote-config.sh"