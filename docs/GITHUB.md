# GitHub Actions Self-Hosted Runner

This document describes the configuration and management of GitHub Actions self-hosted runners in the Kubernetes cluster.

## Overview

The cluster runs self-hosted GitHub Actions runners using the actions-runner-controller, allowing CI/CD workflows to execute within the cluster environment with access to internal services.

## Architecture

The GitHub Actions runner system consists of:
- **actions-runner-controller**: Manages runner lifecycle and scaling
- **RunnerDeployment**: Defines runner configuration for specific repositories
- **GitHub Personal Access Token**: Authenticates with GitHub API

## Installation

### Install actions-runner-controller

```bash
# Add Helm repository
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

# Install controller
helm install github-runner-controller actions-runner-controller/actions-runner-controller \
  --namespace actions-runner-system \
  --create-namespace \
  --set authSecret.github_token=<GITHUB_PAT>
```

### Create Runner Deployment

Runner deployment manifests are stored in `k8s/runner.yaml`.

Apply runner configuration:

```bash
kubectl apply -f k8s/runner.yaml
```

## Personal Access Token Management

The GitHub Personal Access Token (PAT) named "kubensis" is used for runner authentication.

### Token Permissions

Required scopes:
- `repo` (Full control of private repositories)
- `workflow` (Update GitHub Action workflows)
- `admin:org` (if using organization runners)

### Update Token

When regenerating the token, update both the controller secret and repository secrets:

**1. Update controller-manager secret:**

```bash
kubectl patch secret controller-manager -n actions-runner-system \
  --type='json' \
  -p='[{"op": "replace", "path": "/data/github_token", "value":"'$(echo -n '<NEW_TOKEN>' | base64)'"}]'
```

**2. Update repository action secret:**

Navigate to repository settings and update `KOKKO_PAT` secret:
- Repository: `https://github.com/nonzod/personal-website`
- Settings > Secrets and variables > Actions > Repository secrets
- Update `KOKKO_PAT` with new token value

**3. Restart controller:**

```bash
kubectl rollout restart deployment/github-runner-actions-runner-controller -n actions-runner-system
```

**4. Recreate runner deployment:**

```bash
kubectl delete runnerdeployment ntomassoni-runnerdeploy -n http
kubectl apply -f k8s/runner.yaml
```

### Verify Token Update

```bash
# Check controller logs
kubectl logs -n actions-runner-system deployment/github-runner-actions-runner-controller

# List runners
kubectl get runners -n http

# Check specific runner
kubectl describe runner <runner-name> -n http
```

## Runner Configuration

### Example RunnerDeployment

```yaml
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: ntomassoni-runnerdeploy
  namespace: http
spec:
  replicas: 1
  template:
    spec:
      repository: nonzod/personal-website
      labels:
        - self-hosted
        - k8s
      dockerdWithinRunnerContainer: true
      resources:
        limits:
          cpu: "2"
          memory: "2Gi"
        requests:
          cpu: "500m"
          memory: "512Mi"
```

### Configuration Parameters

- **repository**: GitHub repository in format `owner/repo`
- **labels**: Runner labels for workflow targeting
- **dockerdWithinRunnerContainer**: Enable Docker-in-Docker for container builds
- **resources**: CPU and memory limits

## Workflow Integration

Reference the self-hosted runner in workflow YAML:

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: [self-hosted, k8s]
    steps:
      - uses: actions/checkout@v3
      - name: Build and deploy
        run: |
          # Build steps with access to cluster
          kubectl apply -k k8s/
```

## Monitoring and Troubleshooting

### Check Runner Status

```bash
# List all runners
kubectl get runners -A

# Check runner in specific namespace
kubectl get runners -n http

# Describe runner details
kubectl describe runner <runner-name> -n http
```

### View Runner Logs

```bash
# Controller logs
kubectl logs -n actions-runner-system deployment/github-runner-actions-runner-controller

# Runner pod logs
kubectl logs -n http <runner-pod-name>
```

### Common Issues

**Runner not appearing in GitHub:**
- Verify PAT token has correct permissions
- Check controller-manager secret contains valid token
- Restart controller deployment

**Runner stuck in Registration Failed:**
- Token may be expired or invalid
- Check runner logs for specific error
- Recreate runner deployment

**Workflow not using self-hosted runner:**
- Verify workflow `runs-on` matches runner labels
- Check runner is online in repository Settings > Actions > Runners

### Debug Commands

```bash
# Check controller configuration
kubectl get configmap -n actions-runner-system

# View controller events
kubectl get events -n actions-runner-system

# Check runner deployment status
kubectl describe runnerdeployment ntomassoni-runnerdeploy -n http
```

## Security Considerations

- Store PAT securely in Kubernetes secrets
- Use minimal token permissions required
- Rotate tokens periodically
- Limit runner access to specific repositories
- Use namespace isolation for different projects

## Scaling

Scale runners based on workflow demand:

```bash
# Manual scaling
kubectl scale runnerdeployment ntomassoni-runnerdeploy -n http --replicas=3
```

Or configure autoscaling with HorizontalRunnerAutoscaler:

```yaml
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: ntomassoni-runner-autoscaler
  namespace: http
spec:
  scaleTargetRef:
    name: ntomassoni-runnerdeploy
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: TotalNumberOfQueuedAndInProgressWorkflowRuns
    repositoryNames:
    - nonzod/personal-website
```

## Cleanup

Remove runner deployment:

```bash
kubectl delete runnerdeployment ntomassoni-runnerdeploy -n http
```

Uninstall controller:

```bash
helm uninstall github-runner-controller -n actions-runner-system
kubectl delete namespace actions-runner-system
```

## References

- [actions-runner-controller Documentation](https://github.com/actions/actions-runner-controller)
- [GitHub PAT Creation](https://github.com/settings/tokens)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
