# redpanda-prod

The dedicated PROD Redpanda cluster (HOMELAB-47). SANDBOX and DEV share `redpanda-dev`
(see `../redpanda-dev/`), using `sandbox-*` and `dev-*` topics.

| | |
|---|---|
| Brokers | 3 on rasppi5-05, -06 and -10, one per node |
| Per broker | 1 CPU / 2.5 GiB (limits, the same as dev), 100 GiB topolvm disk |
| Retention | 30 days; replication factor 3 |
| Kafka in-cluster | `redpanda-prod-{0,1,2}.redpanda-prod.redpanda-prod.svc.cluster.local:9092`, SASL SCRAM-SHA-512, no TLS |
| Kafka external | `redpanda-prod-{0,1,2}.prod.internal.legohunter.io:31092`, SASL plus Let's Encrypt TLS |
| Console | https://console.redpanda.prod.internal.legohunter.io/overview |
| Users | `admin` (superuser), `prodproducer`, `prodconsumer` |
| Secrets | Infisical **Production**, secret `redpanda-prod-users`, read through `infisical-prod-cluster-secret-store` |

The operator (`redpanda-controller`, v26.1.3, namespace `redpanda-operator`) manages Redpanda
clusters in every namespace, so it manages this one as well; nothing new is installed.

## Before you start

1. **Infisical:** in project `legohunter.io`, environment **Production**, path `/`, add the
   secret **`redpanda-prod-users`** whose value is JSON:
   ```json
   {"admin_password": "<new>", "prodproducer_password": "<new>", "prodconsumer_password": "<new>"}
   ```
   Use new, strong passwords; do not reuse dev's.
2. **Technitium DNS:** add `console.redpanda.prod.internal.legohunter.io` → `10.0.2.80` (Traefik).
   The broker records come later, in step 6.

## Commissioning steps

Each step is applied with `lcms-admin`, on the owner's authorization.

| # | Command | Check |
|---|---|---|
| 0 | `kubectl apply --dry-run=server -f 01-… -f 02-… -f 03-… -f 04-…` | The server validates the Redpanda CR fields; nothing is changed |
| 1 | `kubectl apply -f 01-redpanda-prod-namespace.yaml` | `kubectl get ns redpanda-prod` |
| 2 | `kubectl apply -f 02-redpanda-prod-ip-pool.yaml` | `kubectl get ipaddresspool -n metallb-system` |
| 3 | `kubectl apply -f 03-redpanda-prod-external-secrets.yaml` | Both ExternalSecrets show `SecretSynced`; `redpanda-users` has 3 keys and `redpanda-prod-superusers` has `superusers.txt` (check key names only) |
| 4 | `kubectl apply -f 04-redpanda-prod-cluster.yaml` | The `redpanda-prod` CR is Ready; pods 0–2 are Running on 05/06/10 (`-o wide`); 3 PVCs of 100Gi; the external cert is Ready |
| 5 | `./05-redpanda-prod-users-and-topics.sh` | The script's final listing shows 3 users, 12 `prod-*` topics and the prefixed ACLs |
| 6 | `kubectl get svc -n redpanda-prod -l repdanda.com/type=loadbalancer` | Read which IP each `lb-redpanda-prod-N` got, then add `redpanda-prod-N.prod.internal.legohunter.io` → that IP in Technitium |
| 7 | `kubectl apply -f redpanda-prod-console/console.yaml` | The certificate is Ready, and the console URL loads and shows 3 brokers |

(`repdanda.com/type` is the operator's own misspelling of the label.)

After step 4, check the operator's chosen values:
- `kubectl get sts -n redpanda-prod redpanda-prod -o jsonpath='{.spec.template.spec.affinity}'`
  should show the node affinity (05/06/10) and the operator's default one-broker-per-node
  anti-affinity.
- `rpk cluster config get log_retention_ms` (run in a broker) should print `2592000000`.

## Not like dev, on purpose

- **No hand-made Secrets.** The superusers Secret is built by ExternalSecrets from Infisical; dev
  used `superusers.txt` on rasppi5-01.
- **The console password is not in a ConfigMap.** It comes from the `KAFKA_SASL_PASSWORD`
  environment variable.
- **Pinned, newer images:** Redpanda `v26.1.17` (dev: v26.1.6) and console `v3.14.0` (dev: v3.13.1).
  Bringing the operator and dev up to date, and the move to 26.2, are HOMELAB-49.
- **No external-dns annotation.** DNS records are added by hand in Technitium.
- **Users, topics and ACLs are scripted.** Dev's exist only in the broker.
