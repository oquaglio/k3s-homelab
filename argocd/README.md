# ArgoCD GitOps Setup

This directory contains ArgoCD configuration for managing the K3s homelab using GitOps principles.

## What is ArgoCD?

ArgoCD continuously monitors your GitHub repository and automatically syncs any changes to your Kubernetes cluster. When you push changes to git, ArgoCD deploys them automatically.

## Directory Structure

```
argocd/
├── install.yaml           # ArgoCD installation manifest
├── app-of-apps.yaml       # Parent Application that manages all other apps
├── applications/          # Individual Application manifests for each service
│   ├── n8n.yaml
│   ├── c64-emulator.yaml
│   ├── code-server.yaml
│   ├── homepage.yaml
│   ├── uptime-kuma.yaml
│   ├── portainer.yaml
│   ├── kubernetes-dashboard.yaml
│   └── kube-prometheus-stack.yaml
└── README.md
```

## Initial Setup

1. Install ArgoCD:
   ```bash
   kubectl apply -f argocd/install.yaml
   ```

2. Wait for ArgoCD to be ready:
   ```bash
   kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
   ```

3. Get the initial admin password:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
   ```

4. Access ArgoCD UI:
   - URL: http://localhost:30888
   - Username: admin
   - Password: (from step 3)

5. Deploy the App-of-Apps:
   ```bash
   kubectl apply -f argocd/app-of-apps.yaml
   ```

## How It Works

**App-of-Apps Pattern:**
- `app-of-apps.yaml` is a parent Application that watches `argocd/applications/`
- Each file in `applications/` defines an Application for a service
- ArgoCD automatically creates/updates/deletes Applications based on what's in git

**GitOps Workflow:**
```
1. Edit YAML files in your repo
2. git commit && git push
3. ArgoCD detects change (polls every 3 minutes)
4. ArgoCD syncs cluster to match git
```

## Application Sync Policies

All applications are configured with:
- **automated sync**: Changes in git trigger automatic deployment
- **selfHeal**: Manual changes to cluster are reverted to match git
- **prune**: Resources removed from git are deleted from cluster

## Managing Applications

**Via UI:**
- Access http://localhost:30888
- View all applications, their health, and sync status
- Click on an application to see resources and logs
- Manual sync, refresh, or rollback if needed

**Via CLI:**
```bash
# Install ArgoCD CLI
brew install argocd

# Login
argocd login localhost:30888 --username admin --password <password>

# List applications
argocd app list

# Get application status
argocd app get homepage

# Sync an application manually
argocd app sync homepage

# Rollback
argocd app rollback homepage
```

**Via Git:**
```bash
# Add new application
cat > argocd/applications/my-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/oquaglio/k3s-homelab.git
    targetRevision: HEAD
    path: apps/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

git add argocd/applications/my-app.yaml
git commit -m "Add my-app to ArgoCD"
git push

# ArgoCD detects the new Application and deploys it
```

## Troubleshooting

**Application Out of Sync:**
- Check the ArgoCD UI for diff between git and cluster
- Manual changes to cluster will be reverted by selfHeal
- If you want to keep manual changes, update git to match

**Sync Failed:**
- Check application details in UI for error message
- Common issues: invalid YAML, missing namespace, resource conflicts
- Fix the issue in git and push

**ArgoCD Not Detecting Changes:**
- Default poll interval: 3 minutes
- Force refresh: `argocd app get <app> --refresh`
- Or click "Refresh" in UI

## Repository URL

ArgoCD is configured to watch:
- **Repo**: https://github.com/oquaglio/k3s-homelab.git
- **Branch**: HEAD (tracks main branch)

To change the repository, update the `repoURL` field in all Application manifests.
