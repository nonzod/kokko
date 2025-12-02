# ArgoCD GitOps Configuration

This document describes the ArgoCD setup and GitOps workflow for automated deployment of Kubernetes resources.

## Overview

ArgoCD monitors the Git repository and automatically syncs changes to the cluster. All applications are configured with automatic sync policies including prune and self-heal capabilities.

## ArgoCD Installation

### Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Access ArgoCD UI

Retrieve the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Access the UI via port-forward:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then navigate to `https://localhost:8080` and login with username `admin` and the password retrieved above.

## Application Configuration

All ArgoCD applications are defined in `k8s/argocd/apps/` directory. Each application follows this structure:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <service-name>
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:nonzod/kokko.git
    targetRevision: HEAD
    path: k8s/base/<category>
  destination:
    server: https://kubernetes.default.svc
    namespace: <namespace>
  syncPolicy:
    automated:
      prune: true      # Remove resources deleted from Git
      selfHeal: true   # Revert manual changes to match Git
    syncOptions:
    - CreateNamespace=true
```

## Active Applications

The following ArgoCD applications are configured:

- **domotica**: Home automation services (homeassistant, esphome, samba, mpd-server, rtsp-server, wyoming-piper)
- **http**: Web services (nicolatomassoni)
- **ai**: AI services (cheshirecat)
- **db**: Database services (mysql, qdrant)
- **pihole**: Network ad blocking
- **wireguard**: VPN server
- **cert-manager**: Certificate management
- **github-runner**: GitHub Actions self-hosted runner

## Deploy Applications

Deploy all applications:

```bash
kubectl apply -f k8s/argocd/apps/
```

Deploy specific application:

```bash
kubectl apply -f k8s/argocd/apps/domotica.yaml
```

## Verify Application Status

### Using kubectl

```bash
# List all applications
kubectl get applications -n argocd

# Check specific application
kubectl describe application <app-name> -n argocd
```

### Using ArgoCD CLI

Install ArgoCD CLI:

```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
```

Login and verify:

```bash
# Login
argocd login localhost:8080

# List applications
argocd app list

# Get application details
argocd app get <app-name>

# View sync status
argocd app sync <app-name>
```

## Sync Policies

### Automated Sync

All applications use automated sync with the following settings:

- **prune: true**: Automatically removes resources that are no longer defined in Git
- **selfHeal: true**: Automatically reverts manual changes to match Git state

### Manual Intervention

To temporarily disable auto-sync for maintenance:

```bash
# Disable auto-sync
argocd app set <app-name> --sync-policy none

# Re-enable auto-sync
argocd app set <app-name> --sync-policy automated
```

## Troubleshooting

### Application Out of Sync

Check sync status:

```bash
argocd app get <app-name>
```

Force sync:

```bash
argocd app sync <app-name> --force
```

### View Application Logs

```bash
# ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server

# Application controller logs
kubectl logs -n argocd deployment/argocd-application-controller

# Repo server logs
kubectl logs -n argocd deployment/argocd-repo-server
```

### Webhook Configuration

For automatic sync on Git push, configure webhook in GitHub repository settings:

1. Navigate to repository Settings > Webhooks
2. Add webhook with URL: `https://<argocd-server>/api/webhook`
3. Content type: `application/json`
4. Secret: Configure in ArgoCD ConfigMap
5. Events: Select "Just the push event"

Update ArgoCD ConfigMap to accept webhooks:

```bash
kubectl edit configmap argocd-cm -n argocd
```

Add webhook configuration:

```yaml
data:
  webhook.github.secret: <your-webhook-secret>
```

Restart ArgoCD server:

```bash
kubectl rollout restart deployment argocd-server -n argocd
```

### Resource Hooks

ArgoCD supports resource hooks for advanced deployment scenarios:

- **PreSync**: Execute before sync operation
- **Sync**: Normal resource sync
- **PostSync**: Execute after successful sync
- **SyncFail**: Execute if sync fails

Example hook annotation:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

## Repository Access

The repository uses SSH key authentication. Ensure ArgoCD has access to the private repository:

```bash
# Add repository credentials
argocd repo add git@github.com:nonzod/kokko.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

## Health Checks

ArgoCD performs health checks on resources:

- **Healthy**: Resource is functioning correctly
- **Progressing**: Resource is being created or updated
- **Degraded**: Resource is not functioning correctly
- **Suspended**: Resource is suspended (e.g., CronJob)

Custom health checks can be defined in ArgoCD ConfigMap for specific resource types.

## Best Practices

1. **Use Git branches for testing**: Create feature branches to test changes before merging to main
2. **Review sync status regularly**: Monitor ArgoCD UI for sync errors or degraded resources
3. **Use resource hooks for complex deployments**: Implement PreSync and PostSync hooks for database migrations or configuration updates
4. **Enable notifications**: Configure Slack or email notifications for sync failures
5. **Tag releases**: Use Git tags to track deployment versions

## Configuration Changes

When modifying Kubernetes manifests:

1. Commit changes to Git repository
2. Push to remote repository
3. ArgoCD automatically detects changes
4. Sync operation is triggered automatically
5. Verify deployment in ArgoCD UI or CLI

Manual changes directly to cluster resources will be reverted by ArgoCD self-heal policy.
