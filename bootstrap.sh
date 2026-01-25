#!/bin/bash
set -e

echo "========================================="
echo "K3s Homelab Bootstrap Script"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo -e "${RED}Please do not run as root (don't use sudo)${NC}"
   exit 1
fi

echo -e "${YELLOW}Step 1: Installing K3s...${NC}"
if systemctl is-active --quiet k3s; then
    echo "K3s is already installed and running"
else
    echo "Installing K3s..."
    curl -sfL https://get.k3s.io | sh -
    echo "Waiting for K3s to be ready..."
    sleep 10
fi

echo ""
echo -e "${YELLOW}Step 2: Setting up kubectl configuration...${NC}"
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config

# Add KUBECONFIG to shell config if not already there
if ! grep -q "export KUBECONFIG=" ~/.zshrc 2>/dev/null; then
    echo 'export KUBECONFIG=~/.kube/config' >> ~/.zshrc
    echo "Added KUBECONFIG to ~/.zshrc"
fi

if ! grep -q "export KUBECONFIG=" ~/.bashrc 2>/dev/null; then
    echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
    echo "Added KUBECONFIG to ~/.bashrc"
fi

export KUBECONFIG=~/.kube/config

echo ""
echo -e "${YELLOW}Step 3: Verifying K3s installation...${NC}"
kubectl get nodes

echo ""
echo -e "${YELLOW}Step 4: Creating namespaces...${NC}"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace portainer --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo -e "${YELLOW}Step 5: Installing Helm...${NC}"
if command -v helm &> /dev/null; then
    echo "Helm is already installed"
else
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo ""
echo -e "${YELLOW}Step 6: Adding Helm repositories...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Bootstrap complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Create your secrets: cp secrets.sh.example secrets.sh && vi secrets.sh"
echo "2. Run secrets script: ./secrets.sh"
echo "3. Deploy applications: ./deploy.sh"
echo ""
echo "To access from remote machines:"
echo "1. Run: ./generate-remote-config.sh"
echo "2. Copy the generated config to your laptop"
