# GitHub Actions Runners (ARC) for the LegoHunter org

Self-hosted GitHub Actions runners on the homelab k3s cluster, managed by
[Actions Runner Controller](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/quickstart)
(ARC, "runner scale set" mode). LCMS service repos (e.g. `lego-data-service`, `lego-data-ingress`)
use them through the shared pipeline to deploy into `services-<env>` namespaces with `kubectl`:
`[arc-runner]` for SANDBOX and DEV, and the dedicated `[arc-runner-prod]` for PROD (HOMELAB-29).

This directory is the **source of truth** for the ARC setup. Do not keep edited copies of these
values elsewhere (the old `~/github-arc/` working directory on rasppi5-01 is retired, see
[History](#history)).

## Components

| Thing | Where | Source |
| --- | --- | --- |
| Controller (`arc-controller`) | Helm release, ns `arc-runners` | chart `gha-runner-scale-set-controller` 0.14.1, [helm/arc-controller-values.yaml](helm/arc-controller-values.yaml) |
| Runner scale set (`arc-runner`) | Helm release, ns `arc-runners` | chart `gha-runner-scale-set` 0.14.2, [helm/arc-runner-values.yaml](helm/arc-runner-values.yaml) |
| Runner image `quay.io/tvattima/arc-runner-arm64:k8s-v<N>` | Quay | [Dockerfile](Dockerfile) (actions-runner + kubectl) |
| Deploy identity `arc-runners/arc-deployer` | ServiceAccount + ClusterRole + RoleBindings in `services-sandbox` and `services-dev` | [rbac/arc-deployer.yaml](rbac/arc-deployer.yaml) |
| PROD runner scale set (`arc-runner-prod`) | Helm release, ns `arc-runners` | chart `gha-runner-scale-set` 0.14.2, [helm/arc-runner-prod-values.yaml](helm/arc-runner-prod-values.yaml) |
| PROD deploy identity `arc-runners/arc-deployer-prod` | ServiceAccount + RoleBinding in `services-prod` only (same ClusterRole) | [rbac/arc-deployer-prod.yaml](rbac/arc-deployer-prod.yaml) |
| PROD job guard | job-started hook in the runner image, enabled only on `arc-runner-prod` | [hooks/prod-job-guard.sh](hooks/prod-job-guard.sh) |
| GitHub App credentials | Secret `arc-runners/arc-runners-auth` | created by hand (below); never committed |

`hpm-deployer` (homelab-power-manager) is a separate scale set in the same namespace that shares
the controller and the `arc-runners-auth` Secret. It is not managed from this directory.

## How runners authenticate

* **To GitHub:** the LegoHunter organization GitHub App (`legohunter-arc`), via Secret
  `arc-runners-auth`. No personal access token is used.
* **To Kubernetes:** runner pods run as ServiceAccount `arc-deployer`. Kubernetes mounts a
  short-lived, auto-rotated token and `kubectl` uses in-cluster configuration. No kubeconfig file is
  mounted. The ServiceAccount can only apply/rollout Deployments, Services, IngressRoutes and
  Middlewares in namespaces that have an `arc-deployer` RoleBinding (`services-sandbox`,
  `services-dev`). It cannot read Secrets, delete anything, or act cluster-wide.
* **PROD (HOMELAB-29):** `arc-runner-prod` pods run as `arc-deployer-prod`, which has the same
  ClusterRole but is bound **only** in `services-prod`. `arc-deployer` must never be bound there.

### Why PROD has its own runner

Every job that lands on a runner gets that runner's ServiceAccount rights, whatever branch or
repository it comes from. GitHub Environment approvals and branch rules gate GitHub secrets and pause
jobs, but cannot take a runner's own credentials away. If `arc-deployer` were bound in
`services-prod`, a feature-branch workflow edited to run `kubectl` against PROD would succeed.

So `arc-runner-prod` holds the only PROD rights, and its job-started hook
([hooks/prod-job-guard.sh](hooks/prod-job-guard.sh), enabled by `ACTIONS_RUNNER_HOOK_JOB_STARTED` in
its values) fails every job before its first step unless:

* the event is `push` and the ref is `refs/heads/main` (in both `GITHUB_REF` and the event payload);
* the repository is listed in `PROD_RUNNER_ALLOWED_REPOS` (in the values file).

The LegoHunter org is on the GitHub Free plan, which has only the Default runner group, so the
runner cannot be limited to repositories or workflows in GitHub's settings. The hook does that
instead. The remaining trust is in whoever can push to `main` of an allowlisted repository, so
protect `main` in those repositories.

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

### 3. Deploy identities

```bash
kubectl apply -f github-runner/rbac/arc-deployer.yaml       # also defines the ClusterRole
kubectl apply -f github-runner/rbac/arc-deployer-prod.yaml
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

### 4b. PROD runner scale set

```bash
helm upgrade --install arc-runner-prod   oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set   --version 0.14.2   -f github-runner/helm/arc-runner-prod-values.yaml   --namespace arc-runners
```

### 5. Verify

```bash
# What the runner identity may and may not do (expect yes, yes, no, no):
kubectl auth can-i patch deployments -n services-sandbox --as=system:serviceaccount:arc-runners:arc-deployer
kubectl auth can-i create ingressroutes.traefik.io -n services-sandbox --as=system:serviceaccount:arc-runners:arc-deployer
kubectl auth can-i get secrets -n services-sandbox --as=system:serviceaccount:arc-runners:arc-deployer
kubectl auth can-i patch deployments -n kube-system --as=system:serviceaccount:arc-runners:arc-deployer

# The shared runner must have NO rights in PROD; the PROD runner only there (expect no, yes, no, no):
kubectl auth can-i patch deployments -n services-prod --as=system:serviceaccount:arc-runners:arc-deployer
kubectl auth can-i patch deployments -n services-prod --as=system:serviceaccount:arc-runners:arc-deployer-prod
kubectl auth can-i patch deployments -n services-sandbox --as=system:serviceaccount:arc-runners:arc-deployer-prod
kubectl auth can-i get secrets -n services-prod --as=system:serviceaccount:arc-runners:arc-deployer-prod

kubectl get autoscalingrunnerset -n arc-runners
```

Then re-run a deploy workflow (e.g. a lego-data-ingress PR's "Deploy sandbox" job).

## Routine operations

### Allow deploys to a new namespace

Copy a `RoleBinding` in [rbac/arc-deployer.yaml](rbac/arc-deployer.yaml), change its `namespace`,
commit, and `kubectl apply -f github-runner/rbac/arc-deployer.yaml`. Never for `services-prod`: PROD
belongs to `arc-deployer-prod` only.

### Allow a new service to deploy to PROD

Append `LegoHunter/<service>` to `PROD_RUNNER_ALLOWED_REPOS` in
[helm/arc-runner-prod-values.yaml](helm/arc-runner-prod-values.yaml), commit, and run the step-4b
`helm upgrade`. The service also needs its GitHub Environments
([../new-service-repo/README.md](../new-service-repo/README.md#release-controls-homelab-29)).

### Update the runner image

GitHub deprecates old runner versions every few months. Deploy jobs then stay **queued**, and
`kubectl get ephemeralrunner -n arc-runners` shows runners in state `Outdated` ("Runner is
deprecated"), recreated every minute or two.

1. In [Dockerfile](Dockerfile), bump `FROM ghcr.io/actions/actions-runner:<version>` to the latest
   [release](https://github.com/actions/runner/releases). Keep the kubectl image within one minor
   version of the cluster.
2. In [helm/arc-runner-values.yaml](helm/arc-runner-values.yaml) **and**
   [helm/arc-runner-prod-values.yaml](helm/arc-runner-prod-values.yaml), bump `image:` to
   `quay.io/tvattima/arc-runner-arm64:k8s-v<N+1>` (the image workflow fails if they differ).
3. Commit and push (any `feature/**` branch or `develop`). The workflow
   [arc-runner-image.yml](../.github/workflows/arc-runner-image.yml) builds the arm64 image on a
   GitHub-hosted runner and pushes it to Quay with the org's `QUAY_USERNAME`/`QUAY_TOKEN`. It never
   overwrites an existing tag. The Dockerfile has no `RUN` step, so no emulation is needed.
4. Run the step-4 and step-4b `helm upgrade` commands. Queued deploy jobs then start on the new
   runners.

### Rotate the GitHub App private key

Generate a new key in the GitHub App, recreate `arc-runners-auth` (step 1, using
`kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`), restart the listeners
(`kubectl delete pod -n arc-runners -l app.kubernetes.io/component=runner-scale-set-listener`, which restarts the listeners of every scale set that shares the Secret: `arc-runner`, `arc-runner-prod` and `hpm-deployer`), then
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
| `PROD runner refused this job` in *Set up runner* | The PROD guard hook: the job is not a push to `main`, or the repository is not in `PROD_RUNNER_ALLOWED_REPOS`. |
| Deploy PROD stays queued | `arc-runner-prod` is not installed or its runner is `Outdated` (see *Update the runner image*). |
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
