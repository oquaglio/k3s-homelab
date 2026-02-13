# Homepage Dashboard

[Homepage](https://gethomepage.dev/) is the landing page for the homelab, providing quick access to all services with live health status.

**Access:** `http://<K3S_HOSTNAME>:30000`

## How It Works

Everything is in a single `deployment.yaml` containing six Kubernetes resources:

| Resource | Purpose |
|----------|---------|
| **ServiceAccount** | Identity for the Homepage pod to authenticate with the K8s API |
| **ClusterRole** | Grants read access to namespaces, pods, nodes, ingresses, and metrics |
| **ClusterRoleBinding** | Binds the ClusterRole to the ServiceAccount |
| **ConfigMap** | All Homepage configuration files (see below) |
| **Deployment** | The pod spec running the Homepage container |
| **Service** | NodePort service exposing Homepage on port 30000 |

## ConfigMap Sections

The ConfigMap contains Homepage's YAML config files:

| File | What it configures |
|------|-------------------|
| `bookmarks.yaml` | Quick-link bookmarks (GitHub, K8s docs) |
| `services.yaml` | Service cards — each has an `href` (browser link) and `siteMonitor` (server-side HTTP health check) |
| `widgets.yaml` | Dashboard widgets — K8s cluster stats, CPU/memory usage, date/time |
| `settings.yaml` | Theme, layout, title, favicon |
| `docker.yaml` | Empty — not using Docker integration |
| `kubernetes.yaml` | Tells Homepage to run in K8s cluster mode |

## Health Checks

Each service has two URLs:

- **`href`** — The URL your browser navigates to when you click (uses `K3S_HOSTNAME` + NodePort)
- **`siteMonitor`** — The URL the Homepage pod uses for HTTP health checks (uses internal K8s service DNS, e.g. `http://kube-prometheus-stack-grafana.monitoring:80`)

These are different because the pod can't resolve your LAN hostname (`desktop.lan`), but your browser can't reach internal cluster DNS. `siteMonitor` does an HTTP HEAD request server-side and shows response time on the dashboard.

## Hostname Substitution

The source file uses `localhost` as a placeholder in all `href` URLs. At deploy time, `deploy.sh` substitutes it:

```bash
sed "s/localhost/${K3S_HOSTNAME}/g" apps/homepage/deployment.yaml | kubectl apply -f -
```

The `siteMonitor` URLs use internal K8s DNS names and are not affected by this substitution.

## InitContainer

The Deployment uses an initContainer (`busybox`) to copy ConfigMap files into a writable emptyDir volume. This is needed because Homepage requires a writable config directory, but ConfigMap mounts are read-only.

## Adding a New Service

Add an entry under the appropriate category in `services.yaml`:

```yaml
- My Service:
    icon: my-service.png
    href: http://localhost:30XXX
    description: What it does
    siteMonitor: http://<service-name>.<namespace>:<port>
```

Find the internal service name with:

```bash
kubectl get svc --all-namespaces
```

Then update the layout in `settings.yaml` if you added a new category, and redeploy.
