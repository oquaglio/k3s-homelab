#!/bin/bash
set -e

echo "========================================="
echo "ArgoCD Password Change"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

export KUBECONFIG=~/.kube/config

# Check if ArgoCD is running
if ! kubectl get namespace argocd &> /dev/null; then
    echo -e "${RED}Error: ArgoCD namespace not found${NC}"
    echo "Install ArgoCD first: ./bootstrap-argocd.sh"
    exit 1
fi

# Get current password
echo -e "${YELLOW}Getting current admin password...${NC}"
CURRENT_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

if [ -z "$CURRENT_PASSWORD" ]; then
    echo -e "${RED}Error: Could not retrieve current password${NC}"
    exit 1
fi

echo "Current password: $CURRENT_PASSWORD"
echo ""

# Install argocd CLI if not present
if ! command -v argocd &> /dev/null; then
    echo -e "${YELLOW}Installing ArgoCD CLI...${NC}"

    # Detect OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        brew install argocd
    else
        # Linux
        VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        curl -sSL -o /tmp/argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
        sudo install -m 555 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
        rm /tmp/argocd-linux-amd64
    fi

    echo -e "${GREEN}✓ ArgoCD CLI installed${NC}"
    echo ""
fi

# Login to ArgoCD
echo -e "${YELLOW}Logging in to ArgoCD...${NC}"
argocd login localhost:30888 --username admin --password "$CURRENT_PASSWORD" --insecure

# Prompt for new password
echo ""
echo -e "${YELLOW}Enter new password:${NC}"
read -s NEW_PASSWORD
echo ""
echo -e "${YELLOW}Confirm new password:${NC}"
read -s NEW_PASSWORD_CONFIRM
echo ""

if [ "$NEW_PASSWORD" != "$NEW_PASSWORD_CONFIRM" ]; then
    echo -e "${RED}Error: Passwords don't match${NC}"
    exit 1
fi

# Update password
echo -e "${YELLOW}Updating password...${NC}"
argocd account update-password \
    --current-password "$CURRENT_PASSWORD" \
    --new-password "$NEW_PASSWORD"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Password Updated Successfully!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "New credentials:"
echo "  URL: http://localhost:30888"
echo "  Username: admin"
echo "  Password: <your new password>"
echo ""
echo "Note: The initial admin secret still exists in the cluster."
echo "You can delete it if you want:"
echo "  kubectl delete secret argocd-initial-admin-secret -n argocd"
