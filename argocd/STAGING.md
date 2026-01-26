# Staging Environment

This directory contains ArgoCD Application manifests for a staging environment where you can test changes before promoting to production.

## Key Differences from Production

**Namespace:**
- Production: Various (default, n8n, monitoring, etc.)
- Staging: `staging` (all apps in one namespace)

**Ports:**
- Production: 30XXX
- Staging: 31XXX

**Self-Heal:**
- Production: `selfHeal: true` (auto-reverts manual changes)
- Staging: `selfHeal: false` (allows manual testing)

## Staging Applications

| App | Production Port | Staging Port |
|-----|----------------|--------------|
| n8n | 30555 | 31555 |
| code-server | 30443 | 31443 |
| c64-emulator | 30064 | 31064 |

## Usage

### Option 1: Deploy Entire Staging Environment

```bash
# Deploy the staging app-of-apps
kubectl apply -f argocd/staging-app-of-apps.yaml

# Check status
kubectl get applications -n argocd | grep staging

# All staging apps deploy to staging namespace
kubectl get pods -n staging
```

### Option 2: Deploy Individual Staging Apps

```bash
# Deploy just n8n to staging
kubectl apply -f argocd/staging/n8n.yaml

# Check status
kubectl get application n8n-staging -n argocd
kubectl get pods -n staging -l app=n8n
```

### Option 3: Use test-locally.sh for Ephemeral Testing

For quick tests that don't need GitOps:
```bash
# Test in 'test' namespace (not tracked by ArgoCD)
./test-locally.sh deploy n8n

# Cleanup when done
./test-locally.sh cleanup
```

## Testing Workflow

### Scenario 1: Test a configuration change

```bash
# 1. Make changes to values.yaml
vim charts/n8n/values.yaml

# 2. Commit to a branch (don't push to main yet)
git checkout -b test-n8n-update
git commit -am "Update n8n configuration"
git push -u origin test-n8n-update

# 3. Update staging to use your branch
kubectl patch application n8n-staging -n argocd --type merge -p '
{
  "spec": {
    "source": {
      "targetRevision": "test-n8n-update"
    }
  }
}'

# 4. Watch it deploy
kubectl get pods -n staging -w

# 5. Test the staging app
curl http://localhost:31555

# 6. If good, merge to main for production
git checkout main
git merge test-n8n-update
git push

# Production will auto-sync within 3 minutes
```

### Scenario 2: Test without git commits

```bash
# Use the local test script
./test-locally.sh deploy n8n

# Test at http://localhost:30556
# Cleanup when done
./test-locally.sh cleanup
```

## Cleanup Staging

### Delete individual staging app:
```bash
kubectl delete application n8n-staging -n argocd
```

### Delete entire staging environment:
```bash
# Delete the app-of-apps
kubectl delete application k3s-homelab-staging -n argocd

# Delete staging namespace
kubectl delete namespace staging
```

## Best Practices

1. **Use staging for major changes**
   - New Helm chart versions
   - Resource limit changes
   - Configuration updates that could break things

2. **Use test-locally.sh for quick iterations**
   - Tweaking values
   - Debugging issues
   - Rapid testing

3. **Staging vs Production branches**
   - Keep production on `main` branch
   - Test staging with feature branches
   - Merge to main only after staging validation

4. **Don't run staging 24/7**
   - Deploy when testing
   - Delete when done
   - Saves cluster resources

## Port Allocation

| Range | Purpose |
|-------|---------|
| 30000-30999 | Production services |
| 31000-31999 | Staging services |
| 32000-32767 | Test/ephemeral services |

## Troubleshooting

**Staging app won't sync:**
```bash
# Force refresh
kubectl patch application n8n-staging -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

**Port conflicts:**
```bash
# Check what's using the port
kubectl get svc --all-namespaces | grep <port>

# Change staging port in the Application manifest
```

**Want to test a specific git commit:**
```bash
# Update staging to specific commit SHA
kubectl patch application n8n-staging -n argocd --type merge -p '
{
  "spec": {
    "source": {
      "targetRevision": "abc123def"
    }
  }
}'
```
