# Kube Prometheus Stack Helm Chart

This chart wraps the official [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) Helm chart.

## What's Included

- **Prometheus Operator** - Manages Prometheus instances
- **Prometheus** - Metrics collection and storage
- **Grafana** - Metrics visualization and dashboards
- **Alertmanager** - Alert handling and routing
- **Node Exporter** - Exposes node-level metrics
- **Kube State Metrics** - Kubernetes cluster state metrics

## Access

- **Grafana**: http://localhost:30080
  - Username: `admin`
  - Password: `admin` (change in values.yaml)

- **Prometheus**: http://localhost:30090

## Configuration

Edit `values.yaml` to customize:
- Grafana admin password
- Retention period
- Storage size
- Resource limits

## Why Helm Chart?

Previously used a large 658KB manifests.yaml file which caused issues:
- CRDs and resources in one file caused ordering problems
- ArgoCD couldn't properly sync due to missing CRDs
- Difficult to customize or upgrade

The Helm chart:
- ✅ Handles CRD installation automatically
- ✅ Proper resource ordering
- ✅ Easy to upgrade
- ✅ Industry standard approach
- ✅ Community maintained

## Upgrading

To upgrade to a new version of kube-prometheus-stack:

```bash
# Update Chart.yaml with new version
vim charts/kube-prometheus-stack/Chart.yaml
# Change: version: "56.6.2" to new version

# Update dependencies
cd charts/kube-prometheus-stack
helm dependency update

# Commit and push
git commit -am "chore: upgrade kube-prometheus-stack"
git push

# ArgoCD will sync automatically
```

## Troubleshooting

**Grafana won't start:**
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana
```

**Prometheus issues:**
```bash
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0
```

**Check all resources:**
```bash
kubectl get all -n monitoring
```
