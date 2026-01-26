#!/bin/bash
set -e

echo "========================================="
echo "K3s Homelab Destroy Script (ArgoCD-aware)"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

export KUBECONFIG=~/.kube/config

echo -e "${RED}WARNING: This will delete all deployed applications!${NC}"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

echo ""
echo -e "${YELLOW}Destroying applications...${NC}"
echo ""

# Check if ArgoCD is installed
if kubectl get namespace argocd &> /dev/null; then
    echo -e "${YELLOW}ArgoCD detected. Using GitOps cleanup...${NC}"
    echo ""

    echo -e "${YELLOW}Step 1: Deleting all ArgoCD Applications...${NC}"
    echo "This will trigger cascading deletion of all managed resources."

    # Get list of applications (excluding k3s-homelab app-of-apps)
    APPS=$(kubectl get applications -n argocd -o jsonpath='{.items[?(@.metadata.name!="k3s-homelab")].metadata.name}')

    if [ -n "$APPS" ]; then
        echo "Deleting applications: $APPS"
        for app in $APPS; do
            echo -n "  Deleting $app..."
            kubectl delete application $app -n argocd --ignore-not-found=true 2>/dev/null || true
            echo " done"
        done
    fi

    # Delete the app-of-apps last
    echo -n "  Deleting k3s-homelab (app-of-apps)..."
    kubectl delete application k3s-homelab -n argocd --ignore-not-found=true 2>/dev/null || true
    echo " done"

    echo -e "${GREEN}✓ ArgoCD Applications deleted${NC}"
    echo ""

    echo -e "${YELLOW}Step 2: Waiting for resources to be cleaned up...${NC}"
    echo -n "  Waiting"
    for i in {1..15}; do
        echo -n "."
        sleep 2
    done
    echo " done"
    echo -e "${GREEN}✓ Resources cleaned up${NC}"
    echo ""

    echo -e "${YELLOW}Step 3: Deleting ArgoCD...${NC}"
    kubectl delete namespace argocd --ignore-not-found=true
    echo -e "${GREEN}✓ ArgoCD deleted${NC}"
    echo ""

    echo -e "${YELLOW}Step 4: Cleaning up ArgoCD cluster-scoped resources...${NC}"
    kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/part-of=argocd --ignore-not-found=true 2>/dev/null || true
    kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io --ignore-not-found=true 2>/dev/null || true
    echo -e "${GREEN}✓ Cluster resources cleaned up${NC}"
    echo ""

else
    echo -e "${YELLOW}ArgoCD not detected. Using manual cleanup...${NC}"
    echo ""

    echo -e "${YELLOW}Step 1: Deleting Code-Server (Helm)...${NC}"
    helm uninstall code-server --namespace default 2>/dev/null || true
    echo -e "${GREEN}✓ Code-Server deleted${NC}"
    echo ""

    echo -e "${YELLOW}Step 2: Deleting C64 Emulator (Helm)...${NC}"
    helm uninstall c64 --namespace default 2>/dev/null || true
    echo -e "${GREEN}✓ C64 Emulator deleted${NC}"
    echo ""

    echo -e "${YELLOW}Step 3: Deleting n8n (Helm)...${NC}"
    helm uninstall n8n --namespace n8n 2>/dev/null || true
    echo -e "${GREEN}✓ n8n deleted${NC}"
    echo ""

    echo -e "${YELLOW}Step 4: Deleting Uptime Kuma...${NC}"
    kubectl delete -f monitoring/uptime-kuma/uptime-kuma.yaml --ignore-not-found=true
    echo -e "${GREEN}✓ Uptime Kuma deleted${NC}"
    echo ""

    echo -e "${YELLOW}Step 5: Deleting Kube Prometheus Stack...${NC}"
    kubectl delete -f monitoring/kube-prometheus-stack/manifests.yaml --ignore-not-found=true
    echo -e "${GREEN}✓ Kube Prometheus Stack deleted${NC}"
    echo ""

    echo -e "${YELLOW}Step 6: Deleting Kubernetes Dashboard...${NC}"
    kubectl delete -f monitoring/kubernetes-dashboard/admin-user.yaml --ignore-not-found=true
    kubectl delete -f monitoring/kubernetes-dashboard/dashboard.yaml --ignore-not-found=true
    echo -e "${GREEN}✓ Kubernetes Dashboard deleted${NC}"
    echo ""

    echo -e "${YELLOW}Step 7: Deleting Portainer...${NC}"
    kubectl delete -f monitoring/portainer/portainer.yaml --ignore-not-found=true
    kubectl delete namespace portainer --ignore-not-found=true
    echo -e "${GREEN}✓ Portainer deleted${NC}"
    echo ""

    echo -e "${YELLOW}Step 8: Deleting Homepage...${NC}"
    kubectl delete -f apps/homepage/deployment.yaml --ignore-not-found=true
    echo -e "${GREEN}✓ Homepage deleted${NC}"
    echo ""

    echo -e "${YELLOW}Step 9: Cleaning up secrets...${NC}"
    kubectl delete secret portainer-admin-password -n portainer --ignore-not-found=true 2>/dev/null || true
    kubectl delete secret kube-prometheus-stack-grafana -n monitoring --ignore-not-found=true 2>/dev/null || true
    echo -e "${GREEN}✓ Secrets deleted${NC}"
    echo ""
fi

echo -e "${YELLOW}Step 5: Cleaning up remaining namespaces...${NC}"
kubectl delete namespace n8n monitoring portainer kubernetes-dashboard --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✓ Namespaces deleted${NC}"
echo ""

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}All applications destroyed!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "To completely remove K3s from the system:"
echo "  sudo /usr/local/bin/k3s-uninstall.sh"
echo ""
echo "To redeploy everything:"
if kubectl get namespace argocd &> /dev/null 2>&1 || [ -f "argocd/install.yaml" ]; then
    echo "  ./bootstrap.sh          # Reinstall K3s"
    echo "  ./bootstrap-argocd.sh   # Install ArgoCD (deploys everything from git)"
else
    echo "  ./deploy.sh"
fi
