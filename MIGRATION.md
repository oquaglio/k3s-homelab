# Server Migration Guide

This guide explains how to migrate your K3s homelab to a new server using GitOps.

## Why Migration is Easy with ArgoCD

Your entire cluster configuration is stored in git. Moving to a new server is just:
1. Install K3s on new server
2. Install ArgoCD
3. ArgoCD recreates everything from git

**No manual configuration needed!**

---

## Complete Cluster Rebuild (Same Server)

Use this to start fresh or recover from issues.

### One-Command Rebuild:

```bash
./rebuild-cluster.sh
```

This will:
1. Destroy existing K3s cluster
2. Bootstrap fresh K3s
3. Install ArgoCD
4. Deploy all applications from git

### Manual Rebuild (if script fails):

```bash
# 1. Destroy K3s
sudo /usr/local/bin/k3s-uninstall.sh

# 2. Bootstrap K3s
./bootstrap.sh

# 3. Install ArgoCD
./bootstrap-argocd.sh
```

**Time:** ~5 minutes
**Data loss:** Yes (PersistentVolumes are deleted)

---

## Migrate to New Server

### Scenario 1: Fresh Migration (No Data Preservation)

**On new server:**

```bash
# 1. Install git
sudo dnf install git -y  # Fedora/RHEL
# or
sudo apt install git -y  # Ubuntu/Debian

# 2. Clone your repo
git clone https://github.com/oquaglio/k3s-homelab.git
cd k3s-homelab

# 3. Install K3s
./bootstrap.sh

# 4. Install ArgoCD and deploy everything
./bootstrap-argocd.sh
```

**That's it!** ArgoCD deploys everything from git.

**Time:** ~5 minutes
**Downtime:** As long as old server is down

---

### Scenario 2: Migrate with Data Preservation

If you want to preserve PersistentVolume data (Grafana dashboards, n8n workflows, etc.):

**On old server:**

```bash
# 1. Export PersistentVolume data
mkdir -p ~/homelab-backup

# Grafana
kubectl cp monitoring/kube-prometheus-stack-grafana-<pod-id>:/var/lib/grafana ~/homelab-backup/grafana

# n8n
kubectl cp n8n/n8n-n8n-<pod-id>:/home/node/.n8n ~/homelab-backup/n8n

# Uptime Kuma
kubectl cp monitoring/uptime-kuma-<pod-id>:/app/data ~/homelab-backup/uptime-kuma

# Code-Server
kubectl cp default/code-server-<pod-id>:/config ~/homelab-backup/code-server

# 2. Copy backup to new server
rsync -avz ~/homelab-backup newserver:~/homelab-backup
```

**On new server:**

```bash
# 1. Setup cluster as usual
git clone https://github.com/oquaglio/k3s-homelab.git
cd k3s-homelab
./bootstrap.sh
./bootstrap-argocd.sh

# 2. Wait for all pods to be running
kubectl get pods --all-namespaces

# 3. Restore data
kubectl cp ~/homelab-backup/grafana monitoring/kube-prometheus-stack-grafana-<new-pod-id>:/var/lib/grafana
kubectl cp ~/homelab-backup/n8n n8n/n8n-n8n-<new-pod-id>:/home/node/.n8n
# ... etc

# 4. Restart pods to pick up restored data
kubectl delete pod <pod-name> -n <namespace>
# ArgoCD will recreate them
```

**Time:** ~30 minutes
**Downtime:** As long as old server is down + restore time

---

### Scenario 3: Zero-Downtime Migration (Blue/Green)

Run both servers simultaneously during migration:

**On new server:**

```bash
# 1. Setup cluster
git clone https://github.com/oquaglio/k3s-homelab.git
cd k3s-homelab
./bootstrap.sh
./bootstrap-argocd.sh

# 2. Change all NodePorts to avoid conflicts
# (Only if both servers are on same network)
kubectl patch svc <service> -n <namespace> -p '{"spec":{"ports":[{"nodePort":31XXX}]}}'
```

**Test new server:**
- Access services on new IPs/ports
- Validate everything works

**Switch over:**
- Update DNS/load balancer to point to new server
- Or update client configs to use new server IP

**Decommission old server:**
```bash
# On old server
sudo /usr/local/bin/k3s-uninstall.sh
```

**Time:** Variable
**Downtime:** None (if DNS/LB switch is fast)

---

## What Gets Migrated Automatically

✅ **Automatic (in git):**
- All deployments
- All services
- ConfigMaps
- Secrets (if stored in git - not recommended for production!)
- Helm chart configurations
- ArgoCD Applications

❌ **Manual (not in git):**
- PersistentVolume data (databases, file uploads, etc.)
- Portainer admin password
- Grafana dashboards (unless backed up)
- n8n workflows
- Uptime Kuma monitors

---

## Migration Checklist

**Before migration:**
- [ ] Commit all pending changes to git
- [ ] Push to GitHub
- [ ] Document any manual configurations
- [ ] Export PersistentVolume data if needed
- [ ] Note any external integrations (webhooks, API keys)

**During migration:**
- [ ] Clone repo on new server
- [ ] Run bootstrap.sh
- [ ] Run bootstrap-argocd.sh
- [ ] Wait for all pods to be Running
- [ ] Restore PersistentVolume data if needed

**After migration:**
- [ ] Verify all services are accessible
- [ ] Reconfigure Portainer admin user
- [ ] Restore Grafana dashboards
- [ ] Update external integrations (if IPs changed)
- [ ] Update DNS records (if applicable)

---

## Network Considerations

### Same Network (e.g., same datacenter)
- Keep NodePort values the same
- No DNS changes needed if using same IPs

### Different Network (e.g., different datacenter, home → cloud)
- Update DNS records to point to new server IP
- Update firewall rules
- May need to change NodePort ranges if there are conflicts

### Cloud Migration (e.g., home → AWS/GCP)
- Consider using LoadBalancer instead of NodePort
- Update security groups/firewall rules
- Consider using ingress controller instead of NodePort

---

## Backup Strategy

**Recommended: Regular Git Commits**

Every time you make a change:
```bash
git commit -am "Update configuration"
git push
```

Your git repo IS your backup!

**Optional: PersistentVolume Backups**

For stateful data:
```bash
# Create backup script
cat > backup-volumes.sh << 'EOF'
#!/bin/bash
BACKUP_DIR=~/homelab-backup-$(date +%Y%m%d)
mkdir -p $BACKUP_DIR

# Add kubectl cp commands for each PV
# ...

tar czf homelab-backup-$(date +%Y%m%d).tar.gz $BACKUP_DIR
EOF

chmod +x backup-volumes.sh

# Run weekly
crontab -e
# Add: 0 2 * * 0 /path/to/backup-volumes.sh
```

---

## Disaster Recovery

**Scenario: Server died, need to recover ASAP**

1. **Get new server** (VM, bare metal, cloud instance)

2. **Install OS** (Fedora, Ubuntu, etc.)

3. **Run three commands:**
   ```bash
   git clone https://github.com/oquaglio/k3s-homelab.git
   cd k3s-homelab
   ./rebuild-cluster.sh
   ```

4. **Wait 5 minutes**

5. **Done!** Entire homelab recreated

**Recovery Time Objective (RTO):** ~10 minutes
**Recovery Point Objective (RPO):** Last git push

---

## Testing Migration

**Practice migration before you need it:**

```bash
# On a test VM/server
git clone https://github.com/oquaglio/k3s-homelab.git
cd k3s-homelab
./bootstrap.sh
./bootstrap-argocd.sh

# Verify everything works
kubectl get applications -n argocd
kubectl get pods --all-namespaces
```

This validates:
- Your git repo has everything needed
- Bootstrap process works
- ArgoCD deploys correctly
- No manual steps missing

---

## Common Issues

**Issue: ArgoCD can't pull from private repo**

Solution: Add git credentials
```bash
# Create git secret
kubectl create secret generic git-creds \
  --from-literal=username=your-github-username \
  --from-literal=password=your-github-token \
  -n argocd

# Update Applications to use secret
# (or make repo public for homelab)
```

**Issue: NodePort conflicts on same network**

Solution: Change ports for new server
```bash
# Edit values.yaml files to use different ports
vim charts/n8n/values.yaml
# Change nodePort: 30555 -> nodePort: 31555

git commit -am "Use different ports for new server"
git push
```

**Issue: Can't access services after migration**

Check:
- Firewall rules on new server
- Correct IP address being used
- NodePort services are created: `kubectl get svc --all-namespaces`
- Pods are running: `kubectl get pods --all-namespaces`

---

## Multi-Server Setup (Advanced)

Want to run multiple homelabs?

**Server 1 (production):**
```bash
git clone https://github.com/oquaglio/k3s-homelab.git
cd k3s-homelab
./bootstrap-argocd.sh
# Uses main branch, ports 30XXX
```

**Server 2 (testing):**
```bash
git clone https://github.com/oquaglio/k3s-homelab.git
cd k3s-homelab
git checkout -b testing-server

# Edit all values.yaml to use different ports (31XXX)
# Edit ArgoCD Applications to use "testing-server" branch

./bootstrap-argocd.sh
```

Now you have two independent homelabs from the same repo!

---

## Quick Reference

```bash
# Complete rebuild (same server)
./rebuild-cluster.sh

# Manual rebuild
sudo /usr/local/bin/k3s-uninstall.sh
./bootstrap.sh
./bootstrap-argocd.sh

# Migrate to new server
git clone https://github.com/oquaglio/k3s-homelab.git
cd k3s-homelab
./bootstrap.sh
./bootstrap-argocd.sh

# Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

---

## Summary

**The beauty of GitOps:**
- Your cluster is code
- Code is in git
- Git is everywhere
- Rebuild anytime, anywhere, in minutes

**No more:**
- Manual configuration
- "Snowflake" servers
- Lost documentation
- "How did we set this up again?"

**Just:**
```bash
git clone && ./rebuild-cluster.sh
```

And you're back up!
