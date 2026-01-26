#!/bin/bash
set -e

echo "========================================="
echo "ArgoCD Bootstrap Script"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

export KUBECONFIG=~/.kube/config

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to K3s cluster${NC}"
    echo "Run ./bootstrap.sh first or check if K3s is running: sudo systemctl status k3s"
    exit 1
fi

echo -e "${YELLOW}Step 1: Creating argocd namespace...${NC}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace ready${NC}"
echo ""

echo -e "${YELLOW}Step 2: Installing ArgoCD...${NC}"
kubectl apply -f argocd/install.yaml -n argocd

echo "Waiting for ArgoCD to be ready..."
echo -n "  Waiting for ArgoCD pods"
for i in {1..60}; do
    if kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=5s 2>/dev/null; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""
echo -e "${GREEN}✓ ArgoCD installed${NC}"
echo ""

echo -e "${YELLOW}Step 3: Getting ArgoCD admin password...${NC}"
sleep 5  # Wait a bit for the secret to be created
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
if [ -z "$ARGOCD_PASSWORD" ]; then
    echo -e "${YELLOW}Admin password not yet available. Run this command later to get it:${NC}"
    echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d; echo"
else
    echo -e "${GREEN}ArgoCD admin password: ${ARGOCD_PASSWORD}${NC}"
fi
echo ""

echo -e "${YELLOW}Step 4: Deploying App-of-Apps (k3s-homelab)...${NC}"
kubectl apply -f argocd/app-of-apps.yaml
echo -e "${GREEN}✓ App-of-Apps deployed${NC}"
echo ""

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}ArgoCD Bootstrap Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "ArgoCD is now managing your applications via GitOps!"
echo ""
echo "Access ArgoCD UI:"
echo "  URL: http://localhost:30888"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "ArgoCD is now monitoring: https://github.com/oquaglio/k3s-homelab.git"
echo ""
echo "To deploy changes:"
echo "  1. Edit files in your repo"
echo "  2. git commit && git push"
echo "  3. ArgoCD will auto-sync within 3 minutes"
echo ""
echo "View application status:"
echo "  kubectl get applications -n argocd"
echo ""
echo "All your applications are being deployed by ArgoCD now."
echo "Check the UI at http://localhost:30888 to monitor progress!"
