# External Secrets

One Infisical serves every environment. The secrets are in the organization **LegoHunter-IO**
(slug `lego-hunter-io-jw-2r`), in a single project, **legohunter.io** (slug `legohunter-io-g-ua3`,
ID `dffa021f-4672-4fb1-a321-dc9255d80936`). That project has three per-environment environments, Sandbox
(`sandbox`), Development (`dev`) and Production, plus **Global** (`global`, HOMELAB-76) for secrets
that belong to an account rather than an environment (see [Global environment](#global-environment)).

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

## Global environment

Some secrets belong to one **account**, not to an environment, so every environment must use the same
copy. Keeping three copies in step has already gone wrong: DEV's copy of the BrickLink keys was wrong
and every DEV call failed with `401 SIGNATURE_INVALID` until it was fixed by hand (2026-11-13).

**What goes in Global** (only secrets named `*.yml`; anything else stays per environment):

| Secret | Why it is account-level |
|---|---|
| `bricklink-client-api-keys.yml` | One BrickLink seller account: one consumer key and secret. One IP-bound access token serves every environment, since all of them call BrickLink from the same home IP; after an IP change, re-register one token and update one file. |
| the BrickLink MFA mailbox (name set by the web-form spike) | The IONOS mailbox that receives BrickLink's MFA codes for the website login. One mailbox for the one account. |

Candidates to review before moving them: `bricklink-web.yml` (the BrickLink website login, also one
account), Flickr and Bitly configuration.

**What stays per environment:** database, Kafka, S3 and every infrastructure credential. The rule
"never copy credentials between SANDBOX, DEV and PROD" (workspace `AGENTS.md`) still applies to them;
Global is the only, explicit exception.

**Tradeoff (accepted):** one environment's BrickLink access can't be revoked on its own, and the lower
environments hold the same token as PROD. They already have the same power over the one account; what
keeps SANDBOX and DEV lots private is the non-prod stockroom guard in code, not separate credentials.

**How it reaches the pods:** `infisical-global-cluster-secret-store` reads Global with its own read-only
service token ("LegoHunter-IO Global", Secret `external-secrets/infisical-global-token`). Each
`services-<env>-external-secret` has a second `dataFrom` entry with `sourceRef.storeRef` pointing at it,
so Global's files land in the **same** Secret and mount (`/etc/.credentials`): no Deployment or
application change. A file must live in Global **or** in the environment, never both.

**One-time setup (owner):**
1. In Infisical, add the environment **Global**, slug `global` (Project Settings → Environments). If
   Infisical gives it another slug, change `environmentSlug` in the store before applying.
2. Create the service token **LegoHunter-IO Global**: scope Global, path `/`, read-only. Load it with
   step 2 of [Add an environment](#add-an-environment) as `infisical-global-token`.
3. Add `bricklink-client-api-keys.yml` to Global (and the MFA mailbox secret when the spike names it).
   Leave the per-environment copies in place for now.
4. `kubectl apply -f kubernetes/cluster-secret-stores/infisical-global-cluster-secret-store.yaml` and
   check `kubectl get clustersecretstore infisical-global-cluster-secret-store` shows `Valid` / `True`.

**Cutover, one environment at a time (DEV, then SANDBOX, then PROD):**
1. `kubectl apply -f kubernetes/external-secrets/services-<env>-external-secret.yaml`; wait for
   `SecretSynced`.
2. Delete that environment's own copy of `bricklink-client-api-keys.yml` in Infisical, so it comes only
   from Global; wait one refresh (1 minute) and check `SecretSynced` again.
3. Restart `lego-data-ingress` in that environment (it reads the file only at startup).
4. Check the next BrickLink order sync run: `NO_WORK` or `SUCCEEDED`, not `401`.

After all three: retire the per-environment BrickLink tokens on BrickLink's API token page, keeping
only the one in Global.

**Rollback:** re-apply the previous ExternalSecret from git (one `dataFrom` entry) and put the
environment's copy back in Infisical. `deletionPolicy: Retain` keeps the current Secret if the Global
store ever fails to authenticate, but no environment's Secret updates while that lasts.

## Status

| Environment | Token Secret | Notes |
|---|---|---|
| Sandbox | `infisical-api-token` ("LegoHunter-IO Sandbox") | Working. In this repo the store's projectSlug is corrected to `legohunter-io-g-ua3`; service tokens ignore it, so applying that changes no behaviour. Since 2026-11-09 (HOMELAB-60) `services-sandbox-external-secret` copies only `*.yml`, as DEV and PROD do; `silo-dev-ingress-sandbox` stays out of the pods. |
| Development | `infisical-dev-token` ("LegoHunter-IO Development") | Switched 2026-11-07 (HOMELAB-47). Until then the store used the Sandbox token, so it really read Sandbox. Its only consumer, `redpanda-dev/redpanda-users`, re-synced with identical data. `services-dev-external-secret` (HOMELAB-57) copies only `*.yml`, as PROD does, so `redpanda-dev-users`, `silo-dev-root` and `silo-dev-ingress-dev` never reach the DEV services. |
| Global | `infisical-global-token` ("LegoHunter-IO Global") | HOMELAB-76: store and the second `dataFrom` entry in each service ExternalSecret are in git, **not applied yet**. Waiting on the owner's one-time setup above. |
| Production | `infisical-prod-token` ("LegoHunter-IO Production") | Store created and validated 2026-11-07 (HOMELAB-47). `services-prod-external-secret` (HOMELAB-28) copies **only secrets named `*.yml`** (`regexp: \.yml$`), so the infrastructure credentials kept in Production (`redpanda-prod-users`, `silo-prod-root`, `silo-prod-ingress`) never reach the services. |

Now that Development is switched, `redpanda-dev-users` in Sandbox is unused and can be deleted. Since
HOMELAB-60 `services-sandbox-external-secret` copies only `*.yml`, so non-`.yml` secrets in Sandbox no
longer reach the SANDBOX services.
