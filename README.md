# Kubernetes GitOps Infrastructure Repository

This repository manages the shared infrastructure components for a Kubernetes cluster using **ArgoCD** and **GitOps** principles.

## 🎯 What is GitOps?

**GitOps** is a way of managing infrastructure where:
1. **Git is the single source of truth** - Everything that runs in your cluster is defined in Git
2. **Declarative configuration** - You describe what you want, not how to get there
3. **Automated synchronization** - ArgoCD continuously monitors Git and applies changes automatically
4. **Easy rollback** - Just revert a Git commit to undo changes

**Benefits:**
- Version control for infrastructure (full audit trail)
- Easy collaboration through pull requests
- Disaster recovery (rebuild cluster from Git)
- Consistency across environments

## 🏗️ Repository Structure

```
chad-k8s-gitops/
├── apps/                          # Application definitions
│   ├── ingress-nginx/            # Ingress controller
│   ├── kube-prometheus-stack/    # Prometheus + Grafana monitoring
│   ├── loki/                     # Log aggregation
│   └── promtail/                 # Log collection agent
├── projects/                      # ArgoCD project definitions
│   └── infrastructure.yaml
└── README.md
```

## 📦 Installed Infrastructure Components

### 1. **ingress-nginx** (Traffic Routing)
- **What it does**: Routes external HTTP/HTTPS traffic to your services
- **Why you need it**: Without this, you can't expose services to the internet
- **Namespace**: `ingress-nginx`
- **Access**: External LoadBalancer (check with `kubectl get svc -n ingress-nginx`)

### 2. **kube-prometheus-stack** (Monitoring)
- **What it does**: Collects metrics from your applications and infrastructure
- **Components**:
  - **Prometheus**: Time-series database for metrics
  - **Grafana**: Visualization dashboards
  - **Alertmanager**: Alert routing and management
  - **Node Exporter**: Collects node-level metrics
  - **Kube-state-metrics**: Collects Kubernetes object metrics
- **Namespace**: `monitoring`
- **Grafana Access**: http://grafana.local (update in `kube-prometheus-stack/application.yaml`)
- **Default Login**: admin/admin (⚠️ CHANGE THIS!)

### 3. **Loki** (Log Aggregation)
- **What it does**: Stores and queries logs from all your applications
- **Why it's better than raw logs**: Centralized, searchable, and doesn't require SSH to nodes
- **Namespace**: `monitoring`
- **Integration**: Pre-configured as a Grafana datasource

### 4. **Promtail** (Log Collection)
- **What it does**: Runs on every node and sends logs to Loki
- **How it works**: DaemonSet that reads container logs and forwards them
- **Namespace**: `monitoring`

## 🚀 Getting Started

### Prerequisites
1. A running Kubernetes cluster
2. `kubectl` configured to access your cluster
3. ArgoCD installed in your cluster

### Step 1: Install ArgoCD

If you haven't installed ArgoCD yet:

```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Access ArgoCD UI:**
```bash
# Port-forward to access the UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open in browser: https://localhost:8080
# Username: admin
# Password: (from command above)
```

### Step 2: SSH to Your Cluster Host

If you don't have `kubectl` configured locally, SSH to a machine that has cluster access:

```bash
# SSH to your cluster host
ssh user@your-cluster-host

# Clone this repository
git clone https://github.com/cRotermund/chad-k8s-gitops.git
cd chad-k8s-gitops

# Verify kubectl access
kubectl get nodes
```

**Note**: This keeps your admin kubeconfig secure on the cluster host. For day-to-day operations, you'll:
1. Make changes locally and push to Git
2. SSH to cluster host and `git pull`
3. Let ArgoCD sync automatically (or manually trigger)

### Step 3: Connect This Repository to ArgoCD

**Option A: Using ArgoCD UI**
1. Go to Settings → Repositories
2. Click "Connect Repo"
3. Enter your repository URL
4. Configure authentication (if private repo)

**Option B: Using kubectl**
```bash
# For public repository
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: chad-k8s-gitops
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/cRotermund/chad-k8s-gitops
EOF
```

### Step 4: Deploy the Infrastructure Project

```bash
# Apply the infrastructure project
kubectl apply -f projects/infrastructure.yaml

# Apply all applications
kubectl apply -f apps/ingress-nginx/application.yaml
kubectl apply -f apps/kube-prometheus-stack/application.yaml
kubectl apply -f apps/loki/application.yaml
kubectl apply -f apps/promtail/application.yaml
```

### Step 5: Watch ArgoCD Deploy Everything

```bash
# Watch applications sync
kubectl get applications -n argocd -w

# Or use the ArgoCD CLI
argocd app list
argocd app get ingress-nginx
```

### Step 6: Access ArgoCD UI (Optional)

If you want to manage ArgoCD through the UI from your local machine:

```bash
# On cluster host: Port-forward ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# On local machine: Create SSH tunnel
ssh -L 8080:localhost:8080 user@your-cluster-host

# Open browser: https://localhost:8080
# Username: admin
# Password: (from Step 1)
```

## 🔧 Customization

### Update Grafana Domain
Edit `apps/kube-prometheus-stack/application.yaml`:
```yaml
grafana:
  ingress:
    hosts:
      - grafana.yourdomain.com  # Change this
```

### Adjust Resource Limits
Each application has resource requests/limits defined. Adjust based on your cluster size:
```yaml
resources:
  requests:
    cpu: 100m      # Minimum CPU
    memory: 256Mi  # Minimum memory
  limits:
    cpu: 500m      # Maximum CPU
    memory: 512Mi  # Maximum memory
```

### Change Storage Sizes
Update PVC sizes in the application files:
```yaml
storage: 50Gi  # Prometheus data
storage: 10Gi  # Grafana data
storage: 30Gi  # Loki logs
```

## 📊 Accessing Your Monitoring Stack

### Grafana
1. Find the service: `kubectl get svc -n monitoring | grep grafana`
2. Port-forward: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`
3. Open: http://localhost:3000
4. Login: admin/admin (change this!)

**Pre-configured Dashboards:**
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace
- Node Exporter / Nodes
- And many more!

### Prometheus
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090
```

### Loki (via Grafana)
1. In Grafana, go to Explore
2. Select "Loki" datasource
3. Query logs: `{namespace="default"}` or `{app="myapp"}`

## 🔄 How to Make Changes

1. **Edit files in Git**
   ```bash
   # Example: Change Grafana password
   vim apps/kube-prometheus-stack/application.yaml
   git add .
   git commit -m "Update Grafana password"
   git push
   ```

2. **ArgoCD detects changes** (within 3 minutes by default)

3. **ArgoCD syncs automatically** (because we enabled `automated: true`)

4. **Verify deployment**
   ```bash
   argocd app get kube-prometheus-stack
   ```

### Manual Sync (if needed)
```bash
# Force immediate sync
argocd app sync kube-prometheus-stack

# Or in the UI: Click the "Sync" button
```

## 🐛 Troubleshooting

### Application won't sync
```bash
# Check application status
kubectl get application -n argocd kube-prometheus-stack -o yaml

# View sync errors
argocd app get kube-prometheus-stack

# Check pod status
kubectl get pods -n monitoring
```

### Pods in CrashLoopBackOff
```bash
# View logs
kubectl logs -n monitoring <pod-name>

# Describe pod for events
kubectl describe pod -n monitoring <pod-name>
```

### Ingress not working
```bash
# Check ingress controller is running
kubectl get pods -n ingress-nginx

# Check ingress resource
kubectl get ingress -A

# View ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### Loki not receiving logs
```bash
# Check Promtail is running on all nodes
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail

# Check Promtail logs
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail

# Verify Loki is accessible
kubectl get svc -n monitoring loki-gateway
```

## 📚 Key Concepts Explained

### ArgoCD Application
An **Application** is ArgoCD's way of defining:
- **Source**: Where to get Kubernetes manifests (Git repo, Helm chart, etc.)
- **Destination**: Where to deploy (cluster + namespace)
- **Sync Policy**: How and when to sync

### ArgoCD Project
A **Project** is a logical grouping of applications with:
- **Access control**: What repos and namespaces can be used
- **Resource restrictions**: What Kubernetes resources can be deployed
- **Sync windows**: Optional time-based deployment controls

### Helm Values
**Helm** is a Kubernetes package manager. Our applications use Helm charts with custom values:
```yaml
source:
  repoURL: https://example.com/charts
  chart: my-app
  targetRevision: 1.0.0
  helm:
    values: |
      # Custom configuration here
```

### Sync Policies
```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git
    selfHeal: true   # Fix manual changes
```
- **prune**: Removes resources deleted from Git
- **selfHeal**: Reverts manual kubectl changes back to Git state
- **CreateNamespace**: Creates namespace if it doesn't exist

## 🎓 Next Steps

1. **Secure Grafana**
   - Change the default admin password
   - Set up proper authentication (LDAP, OAuth, etc.)

2. **Configure Alerting**
   - Edit Alertmanager configuration
   - Set up Slack/email notifications
   - Create custom Prometheus alerts

3. **Add Custom Dashboards**
   - Import dashboards from https://grafana.com/grafboards
   - Create dashboards for your applications

4. **Set up TLS/HTTPS**
   - Install cert-manager for automatic TLS certificates
   - Configure Let's Encrypt

5. **Create Application Repositories**
   - Build separate repos for your actual applications
   - Reference this infrastructure in your app deployments

## 📖 Useful Commands

```bash
# ArgoCD
argocd app list                           # List all applications
argocd app get <app-name>                # Get application details
argocd app sync <app-name>               # Force sync
argocd app logs <app-name>               # View application logs
argocd app diff <app-name>               # Preview changes

# Kubectl
kubectl get applications -n argocd       # List ArgoCD applications
kubectl get all -n monitoring            # View all monitoring resources
kubectl top nodes                        # Node resource usage
kubectl top pods -A                      # Pod resource usage

# Logs
kubectl logs -n monitoring -l app=prometheus  # Prometheus logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana  # Grafana logs
```

## 🔗 Useful Links

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Ingress-nginx Documentation](https://kubernetes.github.io/ingress-nginx/)

## 🤝 Contributing

To add new infrastructure components:
1. Create a new directory under `apps/`
2. Add an `application.yaml` file
3. Commit and push to Git
4. Apply: `kubectl apply -f apps/<new-app>/application.yaml`

---

**Remember**: With GitOps, Git is the source of truth. Always make changes through Git, not directly with `kubectl`!
