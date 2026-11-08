# External Secrets

One Infisical serves every environment. The secrets are in the organization **LegoHunter-IO**
(slug `lego-hunter-io-jw-2r`), in a single project, **legohunter.io** (slug `legohunter-io-g-ua3`,
ID `dffa021f-4672-4fb1-a321-dc9255d80936`). That project has three environments: Sandbox
(`sandbox`), Development (`dev`) and Production.

Each environment gets:

| Piece | Name | Where |
|---|---|---|
| Infisical service token: read-only, scoped to that environment and path `/` | `LegoHunter-IO <Environment>` | Infisical project → Access Control → Service Tokens |
| Kubernetes Secret holding the token (key `token`) | sandbox: `infisical-api-token`; dev: `infisical-dev-token`; prod: `infisical-prod-token` | namespace `external-secrets` (made by hand, never in git) |
| ClusterSecretStore | `infisical-<env>-cluster-secret-store` | `kubernetes/cluster-secret-stores/` |
| ExternalSecret copying the whole environment into one Secret | `services-<env>-external-secret` | `kubernetes/external-secrets/` |

**Why service tokens?** Infisical's free plan has no custom project roles. Its built-in roles
(Viewer and so on) cover every environment in a project, so one machine identity per environment
would still be able to read Production. A service token is limited to the environment and path it is
created for, which gives the isolation we need.

Service tokens are a legacy Infisical feature. If an Infisical upgrade removes them, the free-plan
fallback is to move Production into its own Infisical project and use machine identities with the
built-in Viewer role (HOMELAB-47).

## Install the operator

```
kubectl apply -f kubernetes/external-secrets-namespace.yaml
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets -f kubernetes/external-secrets-values.yaml
```

## Add an environment

### 1. Create the service token in Infisical (owner)

Go to **legohunter.io → Access Control → Service Tokens → Create Token** and enter:

- Name: `LegoHunter-IO <Environment>`, e.g. `LegoHunter-IO Production`
- Environment: that environment; Secrets Path: `/`
- Expiration: **Never**
- Permissions: **Read** only (leave Write unchecked)

Infisical shows the token only once. Keep it handy for step 2, and don't paste it anywhere else.

### 2. Load it into the cluster (owner, on rasppi5-01)

This prompts for the token, so it never reaches shell history:

```
read -rs -p "Infisical service token: " TOKEN; echo
kubectl create secret generic infisical-<env>-token -n external-secrets --from-literal=token="$TOKEN"
unset TOKEN
```

### 3. Apply the store and check it

```
kubectl apply -f kubernetes/cluster-secret-stores/infisical-<env>-cluster-secret-store.yaml
kubectl get clustersecretstore infisical-<env>-cluster-secret-store   # expect: store validated
kubectl get externalsecret -A                                         # expect: SecretSynced
```

**Rollback:** the ExternalSecrets use `deletionPolicy: Retain`, so if a store fails to authenticate,
the existing Secrets are kept as they are. Re-apply the previous store definition from git.

## Status

| Environment | Token Secret | Notes |
|---|---|---|
| Sandbox | `infisical-api-token` ("LegoHunter-IO Sandbox") | Working. In this repo the store's projectSlug is corrected to `legohunter-io-g-ua3`; service tokens ignore it, so applying that changes no behaviour. |
| Development | `infisical-dev-token` ("LegoHunter-IO Development") | Switched 2026-11-07 (HOMELAB-47). Until then the store used the Sandbox token, so it really read Sandbox. Its only consumer, `redpanda-dev/redpanda-users`, re-synced with identical data. `services-dev-external-secret` (HOMELAB-57) copies only `*.yml`, as PROD does, so `redpanda-dev-users`, `silo-dev-root` and `silo-dev-ingress-dev` never reach the DEV services. |
| Production | `infisical-prod-token` ("LegoHunter-IO Production") | Store created and validated 2026-11-07 (HOMELAB-47). `services-prod-external-secret` (HOMELAB-28) copies **only secrets named `*.yml`** (`regexp: \.yml$`), so the infrastructure credentials kept in Production (`redpanda-prod-users`, `silo-prod-root`, `silo-prod-ingress`) never reach the services. |

Now that Development is switched, `redpanda-dev-users` in Sandbox is unused and can be deleted. Also move
`pihole-password` out of Sandbox, because `services-sandbox-external-secret` exposes every Sandbox
secret to the SANDBOX services.
