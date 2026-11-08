# silo-dev

The S3 store for **SANDBOX and DEV** (HOMELAB-54). It replaces `minio-dev`, whose MinIO server and
operator are archived upstream. It follows the silo-prod pattern (`../silo-prod/`, HOMELAB-48).

| | |
|---|---|
| Servers | 4 on rasppi5-05, -06, -08, -10, one per node |
| Drives | 4 × 10Gi topolvm per server: 160 GiB raw, about 120 GiB usable (EC:4). minio-dev held 5.6 GiB on 2026-11-08 |
| Memory | request 512Mi, limit 1Gi per server |
| S3 in-cluster | `http://silo-dev.silo-dev.svc.cluster.local:9000` |
| S3 external | `https://api.silo.dev.internal.legohunter.io` |
| Console | https://console.silo.dev.internal.legohunter.io |
| Buckets | `lego-uploads-sandbox`, `lego-photos-sandbox`, `lego-uploads-dev`, `lego-photos-dev` (the same layout as silo-prod) |
| Users | root (Infisical Development `silo-dev-root`); `lcms-ingress-sandbox` (Infisical Sandbox, SANDBOX buckets only); `lcms-ingress-dev` (Infisical Development, DEV buckets only) |
| Events | target `SANDBOX` → redpanda-dev `sandbox-s3-events`; target `DEV` → `dev-s3-events`; both as `devproducer`. Uploads buckets: puts. Photos buckets: deletes |
| Chart | `helm/silo` from github.com/pgsty/silo at tag `RELEASE.2026-10-26T00-00-00Z` (chart 7.0.3), the same as silo-prod |

**Owner decisions (2026-11-08):**
- root in Development, one S3 user per environment;
- DEV buckets, user and events are created now, and HOMELAB-57 only wires ingress;
- lego-data-ingress is the only client;
- the delete events queued in minio-dev are discarded with it, which makes HOMELAB-55 obsolete.

## Before you start (owner)

1. **Infisical**, project `legohunter.io`:
   - **Development**, path `/`:
     - `silo-dev-root`: `{"root_user": "<not minio/admin>", "root_password": "<long random>"}`.
       **No spaces in either value.** The chart's setup job expands them unquoted, so a space
       makes every `mc alias set` fail (it happened on 2026-11-08).
     - `silo-dev-ingress-dev`: `{"access_key": "lcms-ingress-dev", "secret_key": "<long random>"}`
     - `redpanda-dev-users` already exists; Silo uses its `devproducer_password`.
   - **Sandbox**, path `/`:
     - `silo-dev-ingress-sandbox`: `{"access_key": "lcms-ingress-sandbox", "secret_key": "<long random>"}`
2. **DNS:** nothing to add. `console.silo.dev…` and `api.silo.dev…` already resolve to Traefik
   (10.0.2.80) through the `*.dev.internal` wildcard (checked 2026-11-08).

## Commissioning and cutover

Each step is applied with `lcms-admin`, on the owner's authorization.

| # | Command | Check |
|---|---|---|
| 0 | `kubectl apply --dry-run=server -f 01-… -f 02-… -f 04-…`, and `helm upgrade --install silo-dev <chart> -n silo-dev -f 03-silo-dev-values.yaml --dry-run=server` | Nothing changes; the server accepts everything |
| 1 | `kubectl apply -f 01-silo-dev-namespace.yaml -f 02-silo-dev-external-secrets.yaml` | All four ExternalSecrets show `SecretSynced` (names only) |
| 2 | `KUBE_CONTEXT=lcms-admin ../../redpanda/redpanda-dev/05-dev-s3-events-topic.sh` | `dev-s3-events` exists with its three ACLs. `sandbox-s3-events` already exists (HOMELAB-53) |
| 3 | `git clone --depth 1 --branch RELEASE.2026-10-26T00-00-00Z https://github.com/pgsty/silo`, then **without event rules**: `helm upgrade --install silo-dev silo/helm/silo -n silo-dev -f 03-silo-dev-values.yaml --set customCommands=null` | 4 pods Running on 05/06/08/10; 16 PVCs of 10Gi; 16/16 drives online; 4 buckets, 2 users, 2 policies; **no** bucket event rules yet |
| 4 | `kubectl apply -f 04-silo-dev-tls-and-routes.yaml` | The certificate is Ready; the console loads; `https://api.silo.dev…/minio/health/live` returns 200 |
| 5 | Bulk copy: `kubectl apply -f 05-silo-dev-copy-from-minio-dev.yaml`, wait for the Job, read its log | For each bucket, source and destination `mc du` match (size and object count) |
| 6 | **Cutover.** (a) Delete the copy Job and apply it again: a final incremental pass. (b) The owner changes the S3 access/secret in Infisical Sandbox `s3-configuration.yml` to `lcms-ingress-sandbox`. (c) Push the lego-data-ingress HOMELAB-54 branch: `lego.s3.url` = `http://silo-dev.silo-dev.svc.cluster.local:9000`, deployed to SANDBOX | ingress starts and its readiness check is UP |
| 7 | Event rules: `helm upgrade silo-dev silo/helm/silo -n silo-dev -f 03-silo-dev-values.yaml` (now **with** customCommands) | `mc event ls` shows put on both uploads buckets and delete on both photos buckets |
| 8 | End to end in SANDBOX: upload a test photo through the normal path, then delete a `poc/` object | The upload is routed and scaled into `lego-photos-sandbox`. `sandbox-s3-events` gets the events, with principal `lcms-ingress-sandbox` |

## Commissioning record

2026-11-08:
- **Steps 0–5 done.** Steps 6–8 (cutover) and R1–R3 (retirement) are still to come.
- **Store:** 4 servers on rasppi5-08/10/05/06; 16/16 drives online, EC:4, 120 GiB usable.
- **Access:** the Let's Encrypt certificate is valid until 2027-02-06; the API health check and the console return 200.
- **Topic:** `dev-s3-events` was created with its ACLs.
- **Users:** `lcms-ingress-sandbox` can reach its own bucket and is refused on DEV buckets and bucket creation.
- **First install:** it was redone after the root user was corrected; the Secret had a space.
- **Bulk copy:** exact.
  - `lego-uploads-sandbox`: 2.7 GiB, 358 objects.
  - `lego-photos-sandbox`: 2.9 GiB, 2,349 objects.
  - minio-dev had no DEV buckets.
- **Cutover, steps 6–8, done:**
  - **6a:** the final incremental pass found no changes.
  - **6b:** the owner switched Infisical Sandbox `s3-configuration.yml` to `lcms-ingress-sandbox`.
  - **6c:** the lego-data-ingress HOMELAB-54 branch was deployed to SANDBOX; readiness UP.
  - **7:** the event rules were added (helm revision 2).
  - **8:** a dummy upload under `photos/` was routed, rejected and moved to `photos/rejected/` in 451 ms. A `poc/` delete in the photos bucket arrived as `s3:ObjectRemoved:Delete`. The test objects were removed.
- **Retirement, 2026-11-08 (owner go-ahead):**
  - **R1:** the `minio-dev` tenant and namespace were deleted, with all 48 PVs (reclaim `Delete`). Nothing outside the namespace referred to it; silo-dev, SANDBOX ingress (readiness 200) and `monitoring/minio-loki` were unaffected.
  - **R2:** `minio/` was removed from this repo. The `*.minio.dev` DNS records are the owner's to remove.
  - **R3:** HOMELAB-51.
- **Lesson:** `redpanda-dev-users` in Infisical Development held stale `devproducer`/`devconsumer`
  passwords. Silo's targets failed SASL until the owner corrected them, after which the servers
  had a rolling restart. The `admin_password` there is stale too (HOMELAB-50); scripts read
  `redpanda-dev-superusers`.

Between steps 6(a) and 7, nothing new may be written to minio-dev. lego-data-ingress is its only
client, and it switches in 6(c).

## Retiring minio-dev (after step 8 holds)

| # | Command | Check |
|---|---|---|
| R1 | `kubectl delete tenant minio-dev -n minio-dev`, then `kubectl delete namespace minio-dev` | The namespace is gone, with all 48 PVCs (16 in use, 32 orphaned from earlier installs). Their topolvm space is freed. Any delete events still queued in the pods' `/tmp` go with them (owner decision; HOMELAB-55 closes as superseded) |
| R2 | Remove `*.minio.dev.internal.legohunter.io` records from Technitium (owner), and `../../minio/` from this repo | `api.minio.dev…` no longer resolves to the old routes |
| R3 | HOMELAB-51: clean up the minio-dev files on rasppi5-01 | |

**Not retired here:** the `minio-operator` namespace and the `minio-loki` tenant in `monitoring`.
Loki still stores its data in that tenant, so it needs its own decision.

## Notes

- **Notification queue.** `/silo-notify-queue/<env>` is an emptyDir, as in silo-prod.
- **Client.** Silo's client image `pgsty/mc`; the chart's jobs register the target as `mysilo`. The
  image has no `grep`, `sed` or `tail`.
- **Traefik.** Every IngressRoute needs the annotation `kubernetes.io/ingress.class: traefik`.
