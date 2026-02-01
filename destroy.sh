#!/bin/bash
set -e

echo "========================================="
echo "K3s Homelab Destroy Script"
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

echo -e "${YELLOW}Step 4: Deleting Kafka UI (Helm)...${NC}"
helm uninstall kafka-ui --namespace kafka 2>/dev/null || true
echo -e "${GREEN}✓ Kafka UI deleted${NC}"
echo ""

echo -e "${YELLOW}Step 5: Deleting AKHQ (Helm)...${NC}"
helm uninstall akhq --namespace kafka 2>/dev/null || true
echo -e "${GREEN}✓ AKHQ deleted${NC}"
echo ""

echo -e "${YELLOW}Step 6: Deleting Kafka (Helm)...${NC}"
helm uninstall kafka --namespace kafka 2>/dev/null || true
echo -e "${GREEN}✓ Kafka deleted${NC}"
echo ""

echo -e "${YELLOW}Step 7: Deleting MinIO (Helm)...${NC}"
helm uninstall minio --namespace minio 2>/dev/null || true
echo -e "${GREEN}✓ MinIO deleted${NC}"
echo ""

echo -e "${YELLOW}Step 8: Deleting PostgreSQL (Helm)...${NC}"
helm uninstall postgresql --namespace postgresql 2>/dev/null || true
echo -e "${GREEN}✓ PostgreSQL deleted${NC}"
echo ""

echo -e "${YELLOW}Step 9: Deleting Uptime Kuma...${NC}"
kubectl delete -f monitoring/uptime-kuma/uptime-kuma.yaml --ignore-not-found=true
echo -e "${GREEN}✓ Uptime Kuma deleted${NC}"
echo ""

echo -e "${YELLOW}Step 10: Deleting Kube Prometheus Stack...${NC}"
kubectl delete -f monitoring/kube-prometheus-stack/manifests.yaml --ignore-not-found=true
echo -e "${GREEN}✓ Kube Prometheus Stack deleted${NC}"
echo ""

echo -e "${YELLOW}Step 11: Deleting Kubernetes Dashboard...${NC}"
kubectl delete -f monitoring/kubernetes-dashboard/admin-user.yaml --ignore-not-found=true
kubectl delete -f monitoring/kubernetes-dashboard/dashboard.yaml --ignore-not-found=true
echo -e "${GREEN}✓ Kubernetes Dashboard deleted${NC}"
echo ""

echo -e "${YELLOW}Step 12: Deleting Portainer...${NC}"
kubectl delete -f monitoring/portainer/portainer.yaml --ignore-not-found=true
kubectl delete namespace portainer --ignore-not-found=true
echo -e "${GREEN}✓ Portainer deleted${NC}"
echo ""

echo -e "${YELLOW}Step 13: Deleting Homepage...${NC}"
kubectl delete -f apps/homepage/deployment.yaml --ignore-not-found=true
echo -e "${GREEN}✓ Homepage deleted${NC}"
echo ""

echo -e "${YELLOW}Step 14: Cleaning up secrets...${NC}"
kubectl delete secret portainer-admin-password -n portainer --ignore-not-found=true
kubectl delete secret kube-prometheus-stack-grafana -n monitoring --ignore-not-found=true
echo -e "${GREEN}✓ Secrets deleted${NC}"
echo ""

echo -e "${YELLOW}Step 15: Deleting namespaces...${NC}"
kubectl delete namespace kafka --ignore-not-found=true
kubectl delete namespace minio --ignore-not-found=true
kubectl delete namespace postgresql --ignore-not-found=true
kubectl delete namespace n8n --ignore-not-found=true
kubectl delete -f monitoring/kube-prometheus-stack/namespace.yaml --ignore-not-found=true
kubectl delete -f monitoring/portainer/namespace.yaml --ignore-not-found=true
kubectl delete -f monitoring/kubernetes-dashboard/namespace.yaml --ignore-not-found=true
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
echo "  ./deploy.sh"