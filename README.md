# K3s Homelab

Complete K3s homelab setup with monitoring, dashboards, and GitOps workflows.

## 🚀 Quick Start

### First Time Setup

```bash
# 1. Clone this repo
git clone <your-repo-url>
cd k3s-homelab

# 2. Make scripts executable
chmod +x *.sh

# 3. Bootstrap K3s cluster (runs install.sh + setup.sh)
./bootstrap.sh

# 4. Create your secrets
cp secrets.sh.example secrets.sh
vi secrets.sh  # Edit passwords

# 5. Deploy everything (setup + secrets + apps)
./start.sh
```

That's it! Your homelab is running.

### Alternative: Run Steps Individually

```bash
./install.sh   # Install K3s, kubectl, Helm (one-time)
./setup.sh     # Verify cluster and create namespaces
./secrets.sh   # Create secrets (MUST run before deploy)
./deploy.sh    # Deploy all applications
```

**Important:** `secrets.sh` must run before `deploy.sh` - the deploy script checks for required secrets.

## 📦 What's Included

- **Homepage** - Dashboard (port 30000)
- **Portainer** - K8s management UI (port 30777)
- **Kubernetes Dashboard** - Official K8s UI
- **Grafana** - Metrics visualization (port 30080)
- **Prometheus** - Metrics collection (port 30090)
- **Uptime Kuma** - Uptime monitoring (port 30333)
- **PostgreSQL** - Relational database (port 30432)
- **MinIO** - Object storage (API port 30900, Console port 30901)
- **Kafka** - Event streaming platform (port 30092)
- **AKHQ** - Kafka management UI (port 30093)
- **Kafka UI** - Kafka management UI by Provectus (port 30094)
- **Spark** - Distributed data processing with Kafka integration (UI port 30808)
- **n8n** - Workflow automation (port 30555)
- **C64 Emulator** - Commodore 64 in K8s (port 30064)
- **Code-Server** - VS Code in browser (port 30443)
- **Traefik** - Ingress controller (pre-installed with K3s)

## 🎯 Common Tasks

### Check Status
```bash
kubectl get pods --all-namespaces
kubectl get svc --all-namespaces
```

### Access Services

**Web UIs:**
- Homepage: http://localhost:30000 (start here!)
- Portainer: http://localhost:30777
- Grafana: http://localhost:30080
- Prometheus: http://localhost:30090
- Uptime Kuma: http://localhost:30333
- MinIO Console: http://localhost:30901 (minioadmin/minioadmin)
- AKHQ: http://localhost:30093 (Kafka UI)
- Kafka UI: http://localhost:30094 (Kafka UI)
- Spark Master: http://localhost:30808 (cluster dashboard)
- n8n: http://localhost:30555
- C64 Emulator: http://localhost:30064
- Code-Server: http://localhost:30443

**Databases:**
- PostgreSQL: `psql -h localhost -p 30432 -U postgres -d homelab`
- MinIO (S3 API): http://localhost:30900
- Kafka: `kafka-console-producer --bootstrap-server localhost:30092 --topic test`

**Spark + Kafka Integration:**

Spark is pre-loaded with `spark-sql-kafka` connector JARs. To use Kafka as a source/sink from within the cluster:
```python
# PySpark - read from Kafka topic
df = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "kafka-kafka.kafka.svc.cluster.local:9092") \
    .option("subscribe", "my-topic") \
    .load()

# PySpark - write to Kafka topic
df.selectExpr("CAST(key AS STRING)", "CAST(value AS STRING)") \
    .writeStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "kafka-kafka.kafka.svc.cluster.local:9092") \
    .option("topic", "output-topic") \
    .option("checkpointLocation", "/tmp/checkpoint") \
    .start()
```

Submit a job with Kafka JARs:
```bash
kubectl exec -it deploy/spark-spark-master -n spark -- \
  spark-submit --jars /opt/bitnami/spark/custom-jars/* \
  your-app.py
```

**Kubernetes Dashboard:**
```bash
# 1. Start proxy
kubectl proxy

# 2. Get access token
kubectl -n kubernetes-dashboard create token admin-user

# 3. Visit (in browser)
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

### Redeploy Everything
```bash
./destroy.sh  # Remove all apps
./start.sh    # Setup + secrets + deploy fresh
```

### Complete Reset (Nuclear Option)
```bash
# Remove all apps
./destroy.sh

# Uninstall K3s
sudo /usr/local/bin/k3s-uninstall.sh

# Start fresh
./bootstrap.sh
./start.sh
```

## 🌐 Remote Access

To manage the cluster from your laptop:

```bash
# On K3S server
./generate-remote-config.sh

# On another machine
scp <user>@<server-ip>:~/k3s-homelab/configs/k3s-remote.yaml ~/.kube/config-homelab

# Use it
export KUBECONFIG=~/.kube/config-homelab
kubectl get nodes
```

## 📁 Repository Structure

```
k3s-homelab/
├── bootstrap.sh              # Install K3s + tools (one-time)
├── start.sh                  # Full start: setup + secrets + deploy
├── install.sh                # Install K3s, kubectl, Helm
├── setup.sh                  # Verify cluster and create namespaces
├── secrets.sh.example        # Template for secrets
├── deploy.sh                 # Deploy all apps (requires secrets first)
├── destroy.sh                # Remove all apps
├── status.sh                 # Show cluster status
├── generate-remote-config.sh # Generate remote kubeconfig
│
├── apps/
│   ├── nginx/
│   │   └── deployment.yaml   # nginx web server
│   └── homepage/
│       └── deployment.yaml   # Homepage dashboard
│
├── charts/                   # Helm charts
│   ├── postgresql/           # PostgreSQL database
│   ├── minio/                # MinIO object storage
│   ├── kafka/                # Confluent Kafka (KRaft)
│   ├── akhq/                 # AKHQ Kafka management UI
│   ├── kafka-ui/             # Kafka UI (Provectus)
│   ├── spark/                # Apache Spark (master + worker)
│   ├── n8n/                  # Workflow automation
│   ├── code-server/          # VS Code in browser
│   └── c64-emulator/         # Commodore 64 emulator
│
├── monitoring/
│   ├── portainer/
│   │   ├── namespace.yaml    # Portainer namespace
│   │   └── portainer.yaml
│   ├── kubernetes-dashboard/
│   │   ├── namespace.yaml    # Dashboard namespace
│   │   ├── dashboard.yaml
│   │   └── admin-user.yaml
│   ├── kube-prometheus-stack/
│   │   ├── namespace.yaml    # Monitoring namespace
│   │   ├── values.yaml       # Helm values
│   │   └── manifests.yaml    # Generated from Helm
│   └── uptime-kuma/
│       └── uptime-kuma.yaml  # Uptime monitoring
│
└── configs/
    └── k3s-remote.yaml       # Generated by script
```

## 🔐 Security Notes

- **secrets.sh** is gitignored - contains passwords
- **configs/k3s-remote.yaml** contains cluster credentials - don't commit
- Change default passwords in `secrets.sh` before deploying

## 🛠️ Scripts Reference

| Script | Purpose |
|--------|---------|
| `bootstrap.sh` | Install K3s, kubectl, Helm (one-time setup) |
| `start.sh` | Full start: runs setup.sh + secrets.sh + deploy.sh |
| `install.sh` | Install K3s, kubectl, Helm |
| `setup.sh` | Verify cluster and create namespaces |
| `secrets.sh` | Create Kubernetes secrets (must run before deploy) |
| `deploy.sh` | Deploy all applications (requires secrets first) |
| `destroy.sh` | Remove all applications (keeps K3s) |
| `status.sh` | Show cluster status and service URLs |
| `generate-remote-config.sh` | Create kubeconfig for remote access |

## 📚 Learning Resources

**Understanding K8s Concepts:**
- Pods: Your containers
- Deployments: "Keep X copies of this pod running"
- Services: How to access pods (ports, load balancing)
- Namespaces: Logical grouping (monitoring, default, etc.)
- Ingress: Fancy URLs instead of ports

**Useful Commands:**
```bash
# View everything
kubectl get all --all-namespaces

# Describe a pod
kubectl describe pod <pod-name> -n <namespace>

# View logs
kubectl logs <pod-name> -n <namespace>

# Shell into a pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# Port forward a service
kubectl port-forward svc/<service-name> 8080:80 -n <namespace>
```

## 🚧 Roadmap

Future improvements to add:
- [ ] Ingress rules for nice URLs (grafana.homelab.local)
- [ ] Persistent storage setup
- [ ] ArgoCD for GitOps automation
- [ ] Additional apps (wikis, dashboards, etc.)
- [ ] Multi-node setup (add Raspberry Pis)
- [ ] Backup/restore scripts

## 🐛 Troubleshooting

**K3s won't start:**
```bash
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

**Can't connect with kubectl:**
```bash
export KUBECONFIG=~/.kube/config
kubectl cluster-info
```

**Pods stuck in Pending:**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Check for resource issues or image pull errors
```

**Services can't be reached:**
```bash
# Check if service exists
kubectl get svc -n <namespace>

# Check if pods are running
kubectl get pods -n <namespace>

# Check service endpoints
kubectl get endpoints -n <namespace>
```

## 📝 Notes

- K3s runs as a systemd service - starts on boot automatically
- All configs are in git for reproducibility
- Uses declarative YAML - no imperative commands
- Follows GitOps best practices

## 🎓 What You've Learned

By using this homelab, you're learning:
- Kubernetes fundamentals (pods, services, deployments)
- GitOps workflows (infrastructure as code)
- Monitoring with Prometheus + Grafana
- Container orchestration
- Declarative configuration management
- Secrets management
- Multi-namespace organization

---

Built with ❤️ and a lot of `kubectl apply`