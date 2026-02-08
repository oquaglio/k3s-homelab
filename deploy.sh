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

echo -e "${YELLOW}Step 1: Deploying Homepage (Dashboard)...${NC}"
kubectl apply -f apps/homepage/deployment.yaml
kubectl rollout restart deployment homepage 2>/dev/null || true
echo "Waiting for Homepage to be ready..."
kubectl wait --for=condition=ready pod -l app=homepage --timeout=120s || echo -e "${YELLOW}Warning: Homepage pods may still be starting${NC}"
echo -e "${GREEN}✓ Homepage deployed${NC}"
echo ""

echo -e "${YELLOW}Step 2: Deploying Portainer...${NC}"
kubectl apply -f monitoring/portainer/portainer.yaml
echo "Waiting for Portainer to be ready..."
# Wait for deployment to exist first
kubectl wait --for=jsonpath='{.status.replicas}'=1 deployment/portainer -n portainer --timeout=60s 2>/dev/null || sleep 10
# Then wait for pods
kubectl wait --for=condition=ready pod -l app=portainer -n portainer --timeout=120s || echo -e "${YELLOW}Warning: Portainer pods may still be starting${NC}"

# Wait for Portainer API to be ready and initialize admin user
PORTAINER_URL="http://localhost:30777"
echo -n "Waiting for Portainer API to be ready"
ADMIN_CHECK="000"
for i in {1..45}; do
    ADMIN_CHECK=$(curl -s --connect-timeout 2 --max-time 5 -o /dev/null -w "%{http_code}" "${PORTAINER_URL}/api/users/admin/check" 2>/dev/null) || ADMIN_CHECK="000"
    if [ "$ADMIN_CHECK" != "000" ]; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ "$ADMIN_CHECK" = "404" ]; then
    echo "Initializing Portainer admin user..."
    PORTAINER_PASSWORD="${PORTAINER_PASSWORD:-changeMePlease123}"
    curl -s --connect-timeout 5 --max-time 10 -X POST "${PORTAINER_URL}/api/users/admin/init" \
        -H "Content-Type: application/json" \
        -d "{\"Username\":\"admin\",\"Password\":\"${PORTAINER_PASSWORD}\"}" > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Portainer admin user created (admin / ${PORTAINER_PASSWORD})${NC}"
elif [ "$ADMIN_CHECK" = "204" ]; then
    echo "Portainer admin user already exists"
else
    echo "Warning: Could not reach Portainer API (status: ${ADMIN_CHECK})"
fi
echo -e "${GREEN}✓ Portainer deployed${NC}"
echo ""

echo -e "${YELLOW}Step 3: Deploying Kubernetes Dashboard...${NC}"
kubectl apply -f monitoring/kubernetes-dashboard/dashboard.yaml
kubectl apply -f monitoring/kubernetes-dashboard/admin-user.yaml
echo "Waiting for Dashboard to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=kubernetes-dashboard -n kubernetes-dashboard --timeout=120s || echo -e "${YELLOW}Warning: Dashboard pods may still be starting${NC}"
echo -e "${GREEN}✓ Kubernetes Dashboard deployed${NC}"
echo ""

echo -e "${YELLOW}Step 4: Deploying Kube Prometheus Stack (Grafana + Prometheus) via Helm...${NC}"
echo "This may take a few minutes..."
# Create namespace first
kubectl apply -f monitoring/kube-prometheus-stack/namespace.yaml
# Clean up any leftover non-Helm resources that would block Helm installation
kubectl delete secret kube-prometheus-stack-grafana -n monitoring 2>/dev/null || true
# Deploy with Helm (will automatically install CRDs first)
if helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring/kube-prometheus-stack/values.yaml \
  --wait \
  --timeout 5m; then
  echo -e "${GREEN}✓ Kube Prometheus Stack deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy Kube Prometheus Stack${NC}"
  echo "  Check logs with: kubectl get pods -n monitoring"
fi
# Delete the test pod if it exists (it's not needed)
kubectl delete pod kube-prometheus-stack-grafana-test -n monitoring 2>/dev/null || true
echo ""

echo -e "${YELLOW}Step 5: Deploying Grafana Dashboards...${NC}"
kubectl apply -f monitoring/grafana-dashboards/
echo -e "${GREEN}✓ Grafana dashboards deployed${NC}"
echo ""

echo -e "${YELLOW}Step 6: Deploying Uptime Kuma...${NC}"
kubectl apply -f monitoring/uptime-kuma/uptime-kuma.yaml
echo "Waiting for Uptime Kuma to be ready..."
kubectl wait --for=condition=ready pod -l app=uptime-kuma -n monitoring --timeout=120s || echo -e "${YELLOW}Warning: Uptime Kuma pods may still be starting${NC}"
echo -e "${GREEN}✓ Uptime Kuma deployed${NC}"
echo ""

echo -e "${YELLOW}Step 7: Deploying PostgreSQL via Helm...${NC}"
if helm upgrade --install postgresql ./charts/postgresql --namespace postgresql --create-namespace --wait --timeout 120s; then
  echo -e "${GREEN}✓ PostgreSQL deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy PostgreSQL${NC}"
fi
echo ""

echo -e "${YELLOW}Step 8: Deploying pgAdmin (PostgreSQL UI) via Helm...${NC}"
if helm upgrade --install pgadmin ./charts/pgadmin --namespace postgresql --create-namespace --wait --timeout 120s; then
  echo -e "${GREEN}✓ pgAdmin deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy pgAdmin${NC}"
fi
echo ""

echo -e "${YELLOW}Step 9: Deploying MinIO (Object Storage) via Helm...${NC}"
if helm upgrade --install minio ./charts/minio --namespace minio --create-namespace --wait --timeout 120s; then
  echo -e "${GREEN}✓ MinIO deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy MinIO${NC}"
fi
echo ""

echo -e "${YELLOW}Step 10: Deploying Kafka (Event Streaming) via Helm...${NC}"
if helm upgrade --install kafka ./charts/kafka --namespace kafka --create-namespace --wait --timeout 180s; then
  echo -e "${GREEN}✓ Kafka deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy Kafka${NC}"
fi
echo ""

echo -e "${YELLOW}Step 11: Deploying AKHQ (Kafka UI) via Helm...${NC}"
if helm upgrade --install akhq ./charts/akhq --namespace kafka --create-namespace --wait --timeout 120s; then
  echo -e "${GREEN}✓ AKHQ deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy AKHQ${NC}"
fi
echo ""

echo -e "${YELLOW}Step 12: Deploying Kafka UI (Provectus) via Helm...${NC}"
if helm upgrade --install kafka-ui ./charts/kafka-ui --namespace kafka --create-namespace --wait --timeout 120s; then
  echo -e "${GREEN}✓ Kafka UI deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy Kafka UI${NC}"
fi
echo ""

echo -e "${YELLOW}Step 13: Deploying n8n (Workflow Automation) via Helm...${NC}"
if helm upgrade --install n8n ./charts/n8n --namespace n8n --create-namespace --wait --timeout 120s; then
  echo -e "${GREEN}✓ n8n deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy n8n${NC}"
fi
echo ""

echo -e "${YELLOW}Step 14: Deploying Flink (Stream Processing) via Helm...${NC}"
if helm upgrade --install flink ./charts/flink --namespace flink --create-namespace --wait --timeout 180s; then
  echo -e "${GREEN}✓ Flink deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy Flink${NC}"
fi
echo ""

echo -e "${YELLOW}Step 15: Deploying Stock Analyzer (CronJob) via Helm...${NC}"
if helm upgrade --install stock-analyzer ./charts/stock-analyzer --namespace stock-analyzer --create-namespace --wait --timeout 60s; then
  echo -e "${GREEN}✓ Stock Analyzer deployed (Helm) - runs daily at 10 PM UTC${NC}"
else
  echo -e "${RED}✗ Failed to deploy Stock Analyzer${NC}"
fi
echo ""

echo -e "${YELLOW}Step 16: Deploying DOSBox (DOS Games Arcade) via Helm...${NC}"
if helm upgrade --install dosbox ./charts/dosbox --namespace default --wait --timeout 60s; then
  echo -e "${GREEN}✓ DOSBox deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy DOSBox${NC}"
fi
echo ""

echo -e "${YELLOW}Step 17: Deploying C64 Emulator (for fun!)...${NC}"
if helm upgrade --install c64 ./charts/c64-emulator --namespace default --wait --timeout 60s; then
  echo -e "${GREEN}✓ C64 Emulator deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy C64 Emulator${NC}"
fi
echo ""

echo -e "${YELLOW}Step 18: Deploying Code-Server (VS Code in browser)...${NC}"
if helm upgrade --install code-server ./charts/code-server --namespace default --wait --timeout 120s; then
  echo -e "${GREEN}✓ Code-Server deployed (Helm)${NC}"
else
  echo -e "${RED}✗ Failed to deploy Code-Server${NC}"
fi
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
echo -e "${GREEN}Homepage Dashboard: http://localhost:30000${NC}"
echo ""
echo "All services are accessible from the Homepage dashboard!"
echo ""
echo "Direct service URLs:"
echo "  • Homepage:    http://localhost:30000 (start here!)"
echo "  • Portainer:   http://localhost:30777"
echo "  • Grafana:     http://localhost:30080"
echo "  • Prometheus:  http://localhost:30090"
echo "  • Uptime Kuma: http://localhost:30333"
echo "  • PostgreSQL:  localhost:30432 (user: postgres, pass: postgres, db: homelab)"
echo "  • pgAdmin:    http://localhost:30433 (admin@homelab.dev / admin)"
echo "  • MinIO API:   http://localhost:30900 (minioadmin/minioadmin)"
echo "  • MinIO UI:    http://localhost:30901"
echo "  • Kafka:       localhost:30092 (bootstrap server)"
echo "  • AKHQ:       http://localhost:30093 (Kafka UI)"
echo "  • Kafka UI:   http://localhost:30094 (Kafka UI)"
echo "  • Flink UI:   http://localhost:30081 (stream processing dashboard)"
echo "  • n8n:         http://localhost:30555"
echo "  • DOSBox:      http://localhost:30086 (DOS Games Arcade!)"
echo "  • C64:         http://localhost:30064 (retro fun!)"
echo "  • Code-Server: http://localhost:30443 (password: homelab123)"
echo ""
echo "For Kubernetes Dashboard:"
echo "  1. Run: kubectl proxy"
echo "  2. Visit: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
echo "  3. Get token: kubectl -n kubernetes-dashboard create token admin-user"