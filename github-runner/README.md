# GitHub Actions Runners (ARC) for the LegoHunter org

Self-hosted GitHub Actions runners on the homelab k3s cluster, managed by
[Actions Runner Controller](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/quickstart)
(ARC, "runner scale set" mode). LCMS service repos (e.g. `lego-data-service`, `lego-data-ingress`)
use them through `runs-on: [arc-runner]` to deploy into `services-<env>` namespaces with `kubectl`.

This directory is the **source of truth** for the ARC setup. Do not keep edited copies of these
values elsewhere (the old `~/github-arc/` working directory on rasppi5-01 is retired, see
[History](#history)).

## Components

| Thing | Where | Source |
| --- | --- | --- |
| Controller (`arc-controller`) | Helm release, ns `arc-runners` | chart `gha-runner-scale-set-controller` 0.14.1, [helm/arc-controller-values.yaml](helm/arc-controller-values.yaml) |
| Runner scale set (`arc-runner`) | Helm release, ns `arc-runners` | chart `gha-runner-scale-set` 0.14.2, [helm/arc-runner-values.yaml](helm/arc-runner-values.yaml) |
| Runner image `quay.io/tvattima/arc-runner-arm64:k8s-v<N>` | Quay | [Dockerfile](Dockerfile) (actions-runner + kubectl) |
| Deploy identity `arc-runners/arc-deployer` | ServiceAccount + ClusterRole + per-namespace RoleBinding | [rbac/arc-deployer.yaml](rbac/arc-deployer.yaml) |
| GitHub App credentials | Secret `arc-runners/arc-runners-auth` | created by hand (below); never committed |

`hpm-deployer` (homelab-power-manager) is a separate scale set in the same namespace that shares
the controller and the `arc-runners-auth` Secret. It is not managed from this directory.

## How runners authenticate

* **To GitHub:** the LegoHunter organization GitHub App (`legohunter-arc`), via Secret
  `arc-runners-auth`. No personal access token is used.
* **To Kubernetes:** runner pods run as ServiceAccount `arc-deployer`. Kubernetes mounts a
  short-lived, auto-rotated token and `kubectl` uses in-cluster configuration. No kubeconfig file is
  mounted. The ServiceAccount can only apply/rollout Deployments, Services, IngressRoutes and
  Middlewares in namespaces that have an `arc-deployer` RoleBinding (today: `services-sandbox`).
  It cannot read Secrets, delete anything, or act cluster-wide.

All commands below need a cluster-admin kubectl context.

## First-time install

### 1. GitHub App secret

In the LegoHunter organization's GitHub App (`legohunter-arc`): note the App ID and Installation ID
and generate a private key (`.pem`). Then:

```bash
kubectl create secret generic arc-runners-auth \
  --namespace=arc-runners \
  --from-literal=github_app_id=2225355 \
  --from-literal=github_app_installation_id=92798093 \
  --from-file=github_app_private_key=<path-to>/legohunter-arc.<date>.private-key.pem
```

Delete the local `.pem` afterwards (or keep it only in Infisical). Never commit it.

### 2. Controller

```bash
helm upgrade --install arc-controller \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version 0.14.1 \
  -f github-runner/helm/arc-controller-values.yaml \
  --namespace arc-runners
```

### 3. Deploy identity

```bash
kubectl apply -f github-runner/rbac/arc-deployer.yaml
```

### 4. Runner scale set

```bash
helm upgrade --install arc-runner \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.14.2 \
  -f github-runner/helm/arc-runner-values.yaml \
  --namespace arc-runners
```

Do **not** add `--set githubConfigSecret...`: credentials come only from `arc-runners-auth`.

### 5. Verify

```bash
# What the runner identity may and may not do (expect yes, yes, no, no):
kubectl auth can-i patch deployments -n services-sandbox --as=system:serviceaccount:arc-runners:arc-deployer
kubectl auth can-i create ingressroutes.traefik.io -n services-sandbox --as=system:serviceaccount:arc-runners:arc-deployer
kubectl auth can-i get secrets -n services-sandbox --as=system:serviceaccount:arc-runners:arc-deployer
kubectl auth can-i patch deployments -n kube-system --as=system:serviceaccount:arc-runners:arc-deployer

kubectl get autoscalingrunnerset -n arc-runners
```

Then re-run a deploy workflow (e.g. a lego-data-ingress PR's "Deploy sandbox" job).

## Routine operations

### Allow deploys to a new namespace (e.g. `services-dev`)

Copy the `RoleBinding` at the bottom of [rbac/arc-deployer.yaml](rbac/arc-deployer.yaml), change its
`namespace`, commit, and `kubectl apply -f github-runner/rbac/arc-deployer.yaml`.

### Update the runner image

1. Bump `FROM ghcr.io/actions/actions-runner:<version>` (and `KUBECTL_VERSION`, kept within one
   minor version of the cluster) in [Dockerfile](Dockerfile).
2. Build and push (arm64):
   ```bash
   sudo docker build --no-cache -t quay.io/tvattima/arc-runner-arm64:k8s-v<N> github-runner/
   sudo docker push quay.io/tvattima/arc-runner-arm64:k8s-v<N>
   ```
3. Set `image:` in [helm/arc-runner-values.yaml](helm/arc-runner-values.yaml), commit, and run the
   step-4 `helm upgrade` command.

### Rotate the GitHub App private key

Generate a new key in the GitHub App, recreate `arc-runners-auth` (step 1, using
`kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`), restart the listeners
(`kubectl delete pod -n arc-runners -l app.kubernetes.io/component=runner-scale-set-listener,actions.github.com/scale-set-name=arc-runner`), then
delete the old key in GitHub.

### Roll back the runner scale set

```bash
helm history arc-runner -n arc-runners
helm rollback arc-runner <revision> -n arc-runners
```

## Troubleshooting

| Symptom in a deploy job | Likely cause |
| --- | --- |
| `the server has asked for the client to provide credentials` | The runner is not using the in-cluster ServiceAccount token (e.g. a stale `KUBECONFIG` env/mount reintroduced in the values). |
| `... is forbidden: User "system:serviceaccount:arc-runners:arc-deployer" cannot ...` | Target namespace has no `arc-deployer` RoleBinding, or the workflow applies a resource kind not in the ClusterRole. |
| `namespaces "services-dev" not found` | The DEV environment does not exist yet (HOMELAB-26 B2). |
| Listener not starting | `arc-runners-auth` missing/invalid; check `kubectl logs -n arc-runners -l app.kubernetes.io/component=runner-scale-set-listener,actions.github.com/scale-set-name=arc-runner`. |

## History

* **Until 2026-10:** runner pods mounted Secret `arc-runner-kubeconfig`, created from
  `/home/sysadmin/.kube/config`. That was a copy of the k3s **cluster-admin** client certificate
  (`O=system:masters, CN=system:admin`). k3s renews its own copy, but the copied certificate expired
  on **2026-09-28**, which broke every deploy (first noticed on lego-data-ingress PR #72). It also
  gave every workflow job unrevocable cluster-admin. Replaced by the `arc-deployer` ServiceAccount
  (HOMELAB-26).
* **Until 2026-10:** the `arc-runner` release was upgraded with
  `--set githubConfigSecret.github_token=<PAT>`, so it authenticated with a classic PAT stored in
  plaintext, even though `arc-runners-auth` (GitHub App) existed. Now GitHub App only.
* Working files previously lived in `rasppi5-01:~/github-arc/` (values, manifest backups,
  Dockerfile, and plaintext credentials). The Dockerfile and values were moved here.
