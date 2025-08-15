# GitHub local runner

Il workflow è definito in `.github/workflows/deploy.yml` del progetto.
I runner sono in `k8s/runner.yaml`

## Aggiornamento token

Il personal token su GitHub è "kubensis", si aggiorna da (Personal Token)[https://github.com/settings/tokens]
Questo token è settato anche in KOKKO_PAT sulle (actions secrets)[https://github.com/nonzod/personal-website/settings/secrets/actions]

esempio con runner del sito personale hugo

```sh
# aggiornamento secret
kubectl patch secret controller-manager -n actions-runner-system \
  --type='json' \
  -p='[{"op": "replace", "path": "/data/github_token", "value":"'$(echo -n '<NUOVO TOKEN>' | base64)'"}]'

# restart controller
kubectl rollout restart deployment/github-runner-actions-runner-controller -n actions-runner-system

# reset runner
kubectl delete runnerdeployment ntomassoni-runnerdeploy -n http
kubectl apply -f k8s/runner.yaml
kubectl get runners -n http
kubectl describe runner personal-website-runner-<ID> -n http
```
