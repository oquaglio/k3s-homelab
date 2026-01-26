# Testing Guide for K3s Homelab

This guide explains how to test changes before they go to production with ArgoCD managing your cluster.

## Three Testing Approaches

### 1. Quick Local Testing (test-locally.sh)
**Best for:** Rapid iteration, debugging, experimenting

```bash
# Deploy to test namespace (not managed by ArgoCD)
./test-locally.sh deploy n8n

# Check what's running
./test-locally.sh list

# Show what would change in production
./test-locally.sh diff n8n

# Cleanup when done
./test-locally.sh cleanup
```

**Pros:**
- Fast - no git commits needed
- Isolated - runs in separate `test` namespace
- No ArgoCD interference

**Cons:**
- Manual cleanup required
- Not the "real" production deployment path

---

### 2. Staging Environment (ArgoCD)
**Best for:** Testing before production, validating on feature branches

```bash
# Deploy staging environment
kubectl apply -f argocd/staging-app-of-apps.yaml

# All apps deploy to 'staging' namespace with different ports
# n8n staging: http://localhost:31555
# n8n production: http://localhost:30555
```

**Test workflow:**
```bash
# 1. Create feature branch
git checkout -b feature/update-n8n
vim charts/n8n/values.yaml

# 2. Commit and push
git commit -am "Update n8n config"
git push -u origin feature/update-n8n

# 3. Point staging at your branch
kubectl patch application n8n-staging -n argocd --type merge -p '{
  "spec": {
    "source": {
      "targetRevision": "feature/update-n8n"
    }
  }
}'

# 4. Test staging deployment
curl http://localhost:31555

# 5. If good, merge to main
git checkout main
git merge feature/update-n8n
git push

# Production auto-syncs within 3 minutes
```

**Pros:**
- Same deployment path as production
- GitOps workflow
- Can test feature branches

**Cons:**
- Requires git commits
- Uses cluster resources

---

### 3. Preview Changes (kubectl diff)
**Best for:** Seeing what would change without deploying

```bash
# For Helm charts
./test-locally.sh diff n8n

# For raw YAML
kubectl diff -f apps/homepage/deployment.yaml

# For Helm templates
helm template n8n ./charts/n8n | kubectl diff -f -
```

**Pros:**
- No deployment needed
- Fast feedback

**Cons:**
- Doesn't actually test the running application

---

## Testing Workflows

### Workflow 1: Quick Iteration

```bash
# Edit configuration
vim charts/n8n/values.yaml

# Test locally
./test-locally.sh deploy n8n
# Access at http://localhost:30556

# Iterate until it works
vim charts/n8n/values.yaml
./test-locally.sh deploy n8n

# Cleanup test
./test-locally.sh cleanup

# Commit to git
git commit -am "Update n8n configuration"
git push

# ArgoCD deploys to production automatically
```

---

### Workflow 2: Staging Validation

```bash
# Make changes on feature branch
git checkout -b feature/new-app
# ... add new app ...
git commit -am "Add new app"
git push

# Deploy to staging
kubectl apply -f argocd/staging/new-app.yaml
# Edit to point at feature branch
kubectl patch application new-app-staging -n argocd --type merge -p '{
  "spec": {"source": {"targetRevision": "feature/new-app"}}
}'

# Test thoroughly on staging
# ...

# Promote to production
git checkout main
git merge feature/new-app
git push

# Production deploys automatically
```

---

### Workflow 3: Hotfix

```bash
# Production is broken, need to fix fast!

# Option A: Revert via git
git revert HEAD
git push
# ArgoCD auto-reverts production

# Option B: Test fix locally first
vim charts/n8n/values.yaml
./test-locally.sh deploy n8n
# Test the fix at http://localhost:30556

# If it works, commit
git commit -am "fix: resolve n8n issue"
git push
# ArgoCD auto-deploys fix
```

---

## Disabling ArgoCD Auto-Sync (if needed)

Sometimes you need to test manually in production namespace:

```bash
# Disable auto-sync for an app
kubectl patch application n8n -n argocd --type merge -p '{
  "spec": {"syncPolicy": null}
}'

# Now you can manually apply changes
helm upgrade n8n ./charts/n8n -n n8n

# Re-enable auto-sync when done
kubectl patch application n8n -n argocd --type merge -p '{
  "spec": {
    "syncPolicy": {
      "automated": {"prune": true, "selfHeal": true}
    }
  }
}'
```

---

## Port Allocation Reference

| Range | Purpose | Example |
|-------|---------|---------|
| 30000-30999 | Production | n8n: 30555 |
| 31000-31999 | Staging | n8n-staging: 31555 |
| 32000-32767 | Test/ephemeral | n8n-test: 30556 |

---

## Common Testing Scenarios

### Test a new Helm chart version

```bash
# Edit values to use new version
vim charts/n8n/values.yaml
# Change: tag: "1.0.0" -> tag: "1.1.0"

# Test locally
./test-locally.sh deploy n8n

# If good, commit
git commit -am "chore: update n8n to 1.1.0"
git push
```

### Test resource limit changes

```bash
# Edit values
vim charts/n8n/values.yaml

# Preview what changes
./test-locally.sh diff n8n

# Test locally
./test-locally.sh deploy n8n

# Monitor resources
kubectl top pods -n test

# If good, commit
git commit -am "chore: increase n8n memory limits"
git push
```

### Test a new application

```bash
# Create Helm chart
mkdir -p charts/newapp

# Test locally
./test-locally.sh deploy newapp

# Create ArgoCD Application manifest
cat > argocd/applications/newapp.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: newapp
  namespace: argocd
spec:
  # ...
EOF

# Commit everything
git add charts/newapp argocd/applications/newapp.yaml
git commit -m "feat: add newapp"
git push

# ArgoCD deploys automatically
```

---

## Troubleshooting

**ArgoCD keeps reverting my manual changes:**
- ArgoCD has `selfHeal: true` - it reverts manual changes
- Either test in `test` namespace or disable auto-sync temporarily

**Port conflicts:**
```bash
# Find what's using a port
kubectl get svc --all-namespaces | grep <port>
```

**Test deployment not working:**
```bash
# Check test namespace
kubectl get pods -n test
kubectl logs <pod-name> -n test

# Cleanup and retry
./test-locally.sh cleanup
./test-locally.sh deploy <app>
```

**Staging won't sync:**
```bash
# Force refresh
kubectl patch application <app>-staging -n argocd --type merge -p '{
  "metadata": {
    "annotations": {
      "argocd.argoproj.io/refresh": "hard"
    }
  }
}'
```

---

## Best Practices

1. **Use test-locally.sh for development**
   - Fast iteration
   - No git pollution with WIP commits

2. **Use staging for validation**
   - Test on feature branches
   - Validate before merging to main

3. **Keep staging lightweight**
   - Don't run 24/7
   - Deploy only when testing
   - Delete when done

4. **Always test before pushing to main**
   - Main branch = production
   - ArgoCD auto-deploys from main
   - Broken commits = broken production

5. **Use descriptive commit messages**
   - Git history is your deployment log
   - Good messages help debugging

---

## Quick Reference

```bash
# Test locally (ephemeral)
./test-locally.sh deploy <app>
./test-locally.sh list
./test-locally.sh cleanup

# Deploy staging
kubectl apply -f argocd/staging-app-of-apps.yaml

# Point staging at feature branch
kubectl patch application <app>-staging -n argocd --type merge -p '{
  "spec": {"source": {"targetRevision": "<branch>"}}
}'

# Delete staging
kubectl delete application k3s-homelab-staging -n argocd

# Preview changes
./test-locally.sh diff <app>
kubectl diff -f <file>.yaml

# Disable auto-sync temporarily
kubectl patch application <app> -n argocd --type merge -p '{"spec":{"syncPolicy":null}}'

# Re-enable auto-sync
kubectl patch application <app> -n argocd --type merge -p '{
  "spec": {"syncPolicy": {"automated": {"prune": true, "selfHeal": true}}}
}'
```
