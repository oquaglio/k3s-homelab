#!/bin/bash
set -e

echo "========================================="
echo "K3s Homelab Local Testing Script"
echo "========================================="
echo ""
echo "This script allows you to test changes in a separate 'test' namespace"
echo "before committing to git and triggering ArgoCD sync."
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

export KUBECONFIG=~/.kube/config

# Function to show usage
usage() {
    echo "Usage: $0 <command> [app-name]"
    echo ""
    echo "Commands:"
    echo "  deploy <app>   - Deploy an app to 'test' namespace"
    echo "  diff <app>     - Show what would change (kubectl diff)"
    echo "  cleanup        - Delete the test namespace and all test resources"
    echo "  list           - List all test deployments"
    echo ""
    echo "Examples:"
    echo "  $0 deploy n8n              # Deploy n8n to test namespace"
    echo "  $0 deploy code-server      # Deploy code-server to test namespace"
    echo "  $0 diff homepage           # Show diff for homepage"
    echo "  $0 cleanup                 # Delete test namespace"
    echo "  $0 list                    # List test deployments"
    echo ""
    echo "Available apps:"
    echo "  - n8n (Helm chart)"
    echo "  - code-server (Helm chart)"
    echo "  - c64-emulator (Helm chart)"
    echo "  - homepage (YAML)"
    echo "  - uptime-kuma (YAML)"
    echo "  - portainer (YAML)"
    echo "  - kubernetes-dashboard (YAML)"
    echo "  - kube-prometheus-stack (YAML)"
    exit 1
}

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to K3s cluster${NC}"
    echo "Check if K3s is running: sudo systemctl status k3s"
    exit 1
fi

# Parse command
COMMAND=$1
APP=$2

case "$COMMAND" in
    deploy)
        if [ -z "$APP" ]; then
            echo -e "${RED}Error: App name required${NC}"
            usage
        fi

        echo -e "${YELLOW}Deploying $APP to test namespace...${NC}"
        echo ""

        # Create test namespace if it doesn't exist
        if ! kubectl get namespace test &> /dev/null; then
            echo "Creating test namespace..."
            kubectl create namespace test
            echo -e "${GREEN}✓ Test namespace created${NC}"
            echo ""
        fi

        # Deploy based on app type
        case "$APP" in
            n8n)
                echo "Deploying n8n Helm chart to test namespace..."
                helm upgrade --install n8n-test ./charts/n8n \
                    --namespace test \
                    --set service.nodePort=30556 \
                    --wait --timeout 120s
                echo -e "${GREEN}✓ n8n deployed to test namespace${NC}"
                echo ""
                echo "Access at: http://localhost:30556"
                echo "Original (ArgoCD managed): http://localhost:30555"
                ;;

            code-server)
                echo "Deploying code-server Helm chart to test namespace..."
                helm upgrade --install code-server-test ./charts/code-server \
                    --namespace test \
                    --set service.nodePort=30444 \
                    --wait --timeout 120s
                echo -e "${GREEN}✓ code-server deployed to test namespace${NC}"
                echo ""
                echo "Access at: http://localhost:30444"
                echo "Original (ArgoCD managed): http://localhost:30443"
                ;;

            c64-emulator)
                echo "Deploying c64-emulator Helm chart to test namespace..."
                helm upgrade --install c64-test ./charts/c64-emulator \
                    --namespace test \
                    --set service.nodePort=30065 \
                    --wait --timeout 60s
                echo -e "${GREEN}✓ c64-emulator deployed to test namespace${NC}"
                echo ""
                echo "Access at: http://localhost:30065"
                echo "Original (ArgoCD managed): http://localhost:30064"
                ;;

            homepage)
                echo "Deploying homepage to test namespace..."
                kubectl apply -f apps/homepage/deployment.yaml -n test
                kubectl wait --for=condition=ready pod -l app=homepage -n test --timeout=120s 2>/dev/null || true
                echo -e "${GREEN}✓ homepage deployed to test namespace${NC}"
                echo ""
                echo -e "${YELLOW}Note: Homepage NodePort stays at 30000 (conflicts with production)${NC}"
                echo "You may need to manually edit the service to use a different port."
                ;;

            uptime-kuma)
                echo "Deploying uptime-kuma to test namespace..."
                kubectl apply -f monitoring/uptime-kuma/uptime-kuma.yaml -n test
                kubectl wait --for=condition=ready pod -l app=uptime-kuma -n test --timeout=120s 2>/dev/null || true
                echo -e "${GREEN}✓ uptime-kuma deployed to test namespace${NC}"
                ;;

            portainer)
                echo "Deploying portainer to test namespace..."
                kubectl apply -f monitoring/portainer/portainer.yaml -n test
                kubectl wait --for=condition=ready pod -l app=portainer -n test --timeout=120s 2>/dev/null || true
                echo -e "${GREEN}✓ portainer deployed to test namespace${NC}"
                ;;

            kubernetes-dashboard)
                echo "Deploying kubernetes-dashboard to test namespace..."
                kubectl apply -f monitoring/kubernetes-dashboard/dashboard.yaml -n test
                kubectl apply -f monitoring/kubernetes-dashboard/admin-user.yaml -n test
                echo -e "${GREEN}✓ kubernetes-dashboard deployed to test namespace${NC}"
                ;;

            kube-prometheus-stack)
                echo "Deploying kube-prometheus-stack to test namespace..."
                kubectl apply -f monitoring/kube-prometheus-stack/manifests.yaml -n test
                echo -e "${GREEN}✓ kube-prometheus-stack deployed to test namespace${NC}"
                ;;

            *)
                echo -e "${RED}Error: Unknown app '$APP'${NC}"
                usage
                ;;
        esac

        echo ""
        echo -e "${BLUE}Test deployment complete!${NC}"
        echo ""
        echo "To see test pods:"
        echo "  kubectl get pods -n test"
        echo ""
        echo "To cleanup when done:"
        echo "  $0 cleanup"
        ;;

    diff)
        if [ -z "$APP" ]; then
            echo -e "${RED}Error: App name required${NC}"
            usage
        fi

        echo -e "${YELLOW}Showing diff for $APP...${NC}"
        echo ""

        case "$APP" in
            n8n|code-server|c64-emulator)
                echo "Generating Helm template and showing diff..."
                helm template $APP ./charts/$APP | kubectl diff -f - 2>/dev/null || echo "No differences or app not deployed"
                ;;

            homepage)
                kubectl diff -f apps/homepage/deployment.yaml 2>/dev/null || echo "No differences or app not deployed"
                ;;

            uptime-kuma)
                kubectl diff -f monitoring/uptime-kuma/uptime-kuma.yaml 2>/dev/null || echo "No differences or app not deployed"
                ;;

            portainer)
                kubectl diff -f monitoring/portainer/portainer.yaml 2>/dev/null || echo "No differences or app not deployed"
                ;;

            kubernetes-dashboard)
                kubectl diff -f monitoring/kubernetes-dashboard/dashboard.yaml 2>/dev/null || echo "No differences"
                kubectl diff -f monitoring/kubernetes-dashboard/admin-user.yaml 2>/dev/null || echo "No differences"
                ;;

            kube-prometheus-stack)
                kubectl diff -f monitoring/kube-prometheus-stack/manifests.yaml 2>/dev/null || echo "No differences or app not deployed"
                ;;

            *)
                echo -e "${RED}Error: Unknown app '$APP'${NC}"
                usage
                ;;
        esac
        ;;

    cleanup)
        echo -e "${YELLOW}Cleaning up test namespace...${NC}"
        echo ""

        if kubectl get namespace test &> /dev/null; then
            # List what will be deleted
            echo "The following resources will be deleted:"
            kubectl get all -n test 2>/dev/null || true
            echo ""

            echo -e "${RED}Are you sure? (y/N)${NC}"
            read -r CONFIRM

            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                kubectl delete namespace test
                echo -e "${GREEN}✓ Test namespace deleted${NC}"
            else
                echo "Cleanup cancelled"
            fi
        else
            echo "Test namespace does not exist. Nothing to clean up."
        fi
        ;;

    list)
        echo -e "${YELLOW}Test namespace resources:${NC}"
        echo ""

        if kubectl get namespace test &> /dev/null; then
            kubectl get all -n test
        else
            echo "Test namespace does not exist."
            echo ""
            echo "Deploy an app to create it:"
            echo "  $0 deploy n8n"
        fi
        ;;

    *)
        echo -e "${RED}Error: Unknown command '$COMMAND'${NC}"
        usage
        ;;
esac
