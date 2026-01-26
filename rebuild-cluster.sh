#!/bin/bash
set -e

echo "========================================="
echo "K3s Homelab Complete Rebuild"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${RED}WARNING: This will completely destroy and rebuild your K3s cluster!${NC}"
echo "All running pods will be deleted."
echo "PersistentVolumes will be deleted (data loss!)."
echo ""
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

echo ""
echo -e "${YELLOW}Step 1: Destroying existing K3s cluster...${NC}"
if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
    sudo /usr/local/bin/k3s-uninstall.sh
    echo -e "${GREEN}✓ K3s cluster destroyed${NC}"
else
    echo -e "${YELLOW}K3s not installed or already removed${NC}"
fi
echo ""

echo -e "${YELLOW}Step 2: Waiting for cleanup to complete...${NC}"
sleep 5
echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""

echo -e "${YELLOW}Step 3: Bootstrapping fresh K3s cluster...${NC}"
if [ -f "./bootstrap.sh" ]; then
    ./bootstrap.sh
    echo -e "${GREEN}✓ K3s cluster bootstrapped${NC}"
else
    echo -e "${RED}Error: bootstrap.sh not found${NC}"
    exit 1
fi
echo ""

echo -e "${YELLOW}Step 4: Installing ArgoCD and deploying applications...${NC}"
if [ -f "./bootstrap-argocd.sh" ]; then
    ./bootstrap-argocd.sh
    echo -e "${GREEN}✓ ArgoCD deployed - all applications deploying from git${NC}"
else
    echo -e "${RED}Error: bootstrap-argocd.sh not found${NC}"
    exit 1
fi
echo ""

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Cluster Rebuild Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Your entire homelab has been recreated from git!"
echo ""
echo "ArgoCD is deploying all applications from:"
echo "  https://github.com/oquaglio/k3s-homelab.git"
echo ""
echo "Check deployment status:"
echo "  kubectl get applications -n argocd"
echo "  kubectl get pods --all-namespaces"
echo ""
echo "Access ArgoCD UI:"
echo "  URL: http://localhost:30888"
echo "  Username: admin"
echo "  Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo ""
echo "Note: PersistentVolumes were recreated empty."
echo "You'll need to reconfigure applications that store state:"
echo "  - Portainer (create admin user again)"
echo "  - Grafana (dashboards will be default)"
echo "  - n8n (workflows lost)"
echo "  - Uptime Kuma (monitors lost)"
