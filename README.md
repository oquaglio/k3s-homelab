# K3s Homelab with GitOps

Complete K3s homelab setup with ArgoCD, monitoring, automation, and comprehensive testing workflows.

## 🚀 Quick Start

### First Time Setup

```bash
# 1. Clone this repo
git clone https://github.com/oquaglio/k3s-homelab.git
cd k3s-homelab

# 2. Bootstrap K3s cluster
./bootstrap.sh

# 3. Deploy ArgoCD and all applications from git
./bootstrap-argocd.sh
```

**That's it!** ArgoCD deploys everything from git automatically.

### Complete Rebuild (destroy and recreate)

```bash
./rebuild-cluster.sh
```

This destroys and rebuilds your entire cluster from git in ~5 minutes.

---

## 📦 What's Included

### Monitoring
- **Grafana** - Metrics visualization (http://localhost:30080)
- **Prometheus** - Metrics collection (http://localhost:30090)
- **Uptime Kuma** - Uptime monitoring (http://localhost:30333)
- **Portainer** - Container management (http://localhost:30777)

### Automation
- **n8n** - Workflow automation (http://localhost:30555)

### Development
- **Code-Server** - VS Code in browser (http://localhost:30888)

### Fun
- **C64 Emulator** - Commodore 64 BASIC (http://localhost:30064)

### Cluster Management
- **ArgoCD** - GitOps continuous delivery (http://localhost:30888)
- **Kubernetes Dashboard** - Official K8s UI (requires kubectl proxy)
- **Homepage** - Unified dashboard (http://localhost:30000)

---

## 🎯 How GitOps Works

**Before (Manual):**
```bash
vim apps/homepage/deployment.yaml
./deploy.sh  # Manual deployment
```

**After (GitOps):**
```bash
vim apps/homepage/deployment.yaml
git commit -am "Update homepage"
git push
# ArgoCD auto-deploys within 3 minutes
```

**Benefits:**
- ✅ Git is source of truth
- ✅ Self-healing (reverts manual changes)
- ✅ Audit trail (git history)
- ✅ Easy rollback (`git revert`)
- ✅ Disaster recovery (rebuild from git)

---

## 🧪 Testing Workflows

Three ways to test changes:

### 1. Quick Local Testing
```bash
./test-locally.sh deploy n8n       # Deploy to test namespace
./test-locally.sh diff n8n         # Preview changes
./test-locally.sh cleanup          # Remove test resources
```

### 2. Staging Environment
```bash
kubectl apply -f argocd/staging-app-of-apps.yaml
# Apps deploy to staging namespace with different ports
```

### 3. Preview Only
```bash
./test-locally.sh diff <app>
kubectl diff -f <file>.yaml
```

See [TESTING.md](TESTING.md) for complete workflows.

---

## 📋 Common Tasks

### Deploy Changes
```bash
# Edit configuration
vim charts/n8n/values.yaml

# Test locally (optional)
./test-locally.sh deploy n8n

# Commit and push
git commit -am "Update n8n config"
git push

# ArgoCD deploys automatically within 3 minutes
```

### Check Deployment Status
```bash
# ArgoCD applications
kubectl get applications -n argocd

# All pods
kubectl get pods --all-namespaces

# ArgoCD UI
open http://localhost:30888
# Username: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Destroy Everything
```bash
./destroy.sh  # ArgoCD-aware cleanup
```

### Complete Rebuild
```bash
./rebuild-cluster.sh  # Destroy and recreate from git
```

---

## 🔄 Migrating to New Server

```bash
# On new server
git clone https://github.com/oquaglio/k3s-homelab.git
cd k3s-homelab
./bootstrap.sh
./bootstrap-argocd.sh
```

That's it! See [MIGRATION.md](MIGRATION.md) for details.

---

## 📚 Documentation

- **[TESTING.md](TESTING.md)** - Testing workflows and best practices
- **[MIGRATION.md](MIGRATION.md)** - Server migration and disaster recovery
- **[argocd/README.md](argocd/README.md)** - ArgoCD setup and management
- **[argocd/STAGING.md](argocd/STAGING.md)** - Staging environment guide

---

## 🛠️ Scripts Reference

| Script | Purpose |
|--------|---------|
| `bootstrap.sh` | Install K3s and configure cluster |
| `bootstrap-argocd.sh` | Install ArgoCD and deploy all apps from git |
| `rebuild-cluster.sh` | Destroy and recreate entire cluster |
| `deploy.sh` | Manual deployment (legacy, use ArgoCD instead) |
| `destroy.sh` | Delete all applications (ArgoCD-aware) |
| `test-locally.sh` | Test changes in isolated namespace |

---

## 📁 Repository Structure

```
.
├── apps/                      # Application manifests
│   └── homepage/              # Homepage dashboard
├── charts/                    # Helm charts
│   ├── n8n/                   # n8n workflow automation
│   ├── code-server/           # VS Code in browser
│   └── c64-emulator/          # Commodore 64 emulator
├── monitoring/                # Monitoring stack
│   ├── kube-prometheus-stack/ # Grafana + Prometheus
│   ├── uptime-kuma/           # Uptime monitoring
│   ├── portainer/             # Container management
│   └── kubernetes-dashboard/  # K8s dashboard
├── argocd/                    # ArgoCD configuration
│   ├── applications/          # Application manifests
│   ├── staging/               # Staging environment
│   ├── app-of-apps.yaml       # Production app-of-apps
│   └── staging-app-of-apps.yaml # Staging app-of-apps
├── bootstrap.sh               # K3s installation
├── bootstrap-argocd.sh        # ArgoCD installation
├── rebuild-cluster.sh         # Complete rebuild
├── deploy.sh                  # Manual deployment (legacy)
├── destroy.sh                 # Cleanup script
├── test-locally.sh            # Local testing
└── README.md                  # This file
```

---

## 🔧 Requirements

- **OS:** Linux (tested on Fedora/RHEL/Ubuntu)
- **CPU:** 2+ cores
- **RAM:** 4GB+ (8GB recommended)
- **Disk:** 20GB+
- **Network:** Internet connection for pulling images

---

## 🌟 Features

✅ **GitOps with ArgoCD**
- Continuous deployment from git
- Self-healing applications
- Automatic sync within 3 minutes

✅ **Comprehensive Testing**
- Local testing in isolated namespaces
- Staging environment for validation
- Preview changes before deploying

✅ **Complete Monitoring Stack**
- Grafana dashboards
- Prometheus metrics
- Uptime monitoring
- Container management

✅ **Developer Tools**
- VS Code in browser
- Workflow automation
- Git-based deployments

✅ **Disaster Recovery**
- Rebuild entire cluster in 5 minutes
- Migrate to new server easily
- Everything defined in git

---

## 🚨 Important Notes

**PersistentVolumes:**
- Data stored in PVs is lost on rebuild
- Backup important data before rebuilding
- See [MIGRATION.md](MIGRATION.md) for backup strategies

**ArgoCD Management:**
- All changes should go through git
- Manual changes will be reverted by ArgoCD
- Use `test-locally.sh` for testing outside GitOps

**Port Allocation:**
- Production: 30000-30999
- Staging: 31000-31999
- Testing: 32000-32767

---

## 🤝 Contributing

This is a personal homelab project, but feel free to:
- Fork for your own use
- Submit issues for bugs
- Share improvements via PRs

---

## 📝 License

MIT License - see LICENSE file for details

---

## 🙏 Acknowledgments

Built with:
- [K3s](https://k3s.io/) - Lightweight Kubernetes
- [ArgoCD](https://argoproj.github.io/cd/) - GitOps continuous delivery
- [Helm](https://helm.sh/) - Kubernetes package manager
- [Prometheus](https://prometheus.io/) - Monitoring and alerting
- [Grafana](https://grafana.com/) - Metrics visualization
- [n8n](https://n8n.io/) - Workflow automation
- [Code-Server](https://github.com/coder/code-server) - VS Code in browser
- [Uptime Kuma](https://github.com/louislam/uptime-kuma) - Uptime monitoring
- [Portainer](https://www.portainer.io/) - Container management
- [Homepage](https://gethomepage.dev/) - Application dashboard

---

## 🏁 Quick Start Cheatsheet

```bash
# First time setup
git clone https://github.com/oquaglio/k3s-homelab.git
cd k3s-homelab
./bootstrap.sh && ./bootstrap-argocd.sh

# Make a change
vim charts/n8n/values.yaml
git commit -am "Update n8n" && git push

# Test locally first
./test-locally.sh deploy n8n
./test-locally.sh cleanup

# Check status
kubectl get applications -n argocd
kubectl get pods --all-namespaces

# Rebuild everything
./rebuild-cluster.sh

# Migrate to new server
git clone && ./bootstrap.sh && ./bootstrap-argocd.sh
```

**Access services:** http://localhost:30000 (Homepage has links to everything)

**ArgoCD UI:** http://localhost:30888 (admin / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`)
