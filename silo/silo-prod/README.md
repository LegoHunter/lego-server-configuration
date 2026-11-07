# silo-prod

The dedicated PROD S3 store (HOMELAB-48). It runs [Silo](https://github.com/pgsty/silo), a maintained
fork of MinIO. MinIO's open-source server and operator were archived upstream in 2026. A proof of
concept on 2026-11-07 showed that Silo's bucket events reach redpanda-prod over SCRAM-SHA-512 in
exactly the S3 event format lego-data-ingress parses.

SANDBOX and DEV still use `minio-dev`, until `silo-dev` replaces it (HOMELAB-54).

| | |
|---|---|
| Servers | 4 on rasppi5-07, -08, -09, -10, one per node |
| Drives | 4 × 75Gi topolvm per server: 1.2 TiB raw, about 900 GiB usable (EC:4) |
| Memory | request 1Gi, limit 2Gi per server |
| S3 in-cluster | `http://silo-prod.silo-prod.svc.cluster.local:9000` |
| S3 external | `https://api.silo.prod.internal.legohunter.io` |
| Console | https://console.silo.prod.internal.legohunter.io |
| Buckets | `lego-uploads-prod` (everything that comes in: `photos/`, `bricklink/…`, `rebrickable/…`) and `lego-photos-prod` (the final scaled photos), the same layout as SANDBOX's `lego-uploads-sandbox` / `lego-photos-sandbox` |
| Users | root (from Infisical) and `lcms-ingress` (policy `lcms-ingress-prod`: objects in the two buckets only) |
| Events | `lego-uploads-prod` puts and `lego-photos-prod` deletes → redpanda-prod `prod-s3-events`, as `prodproducer` |
| Chart | `helm/silo` from github.com/pgsty/silo at tag `RELEASE.2026-10-26T00-00-00Z` (chart 7.0.3); images pinned to the same release |

The names follow the owner's rule: infrastructure is called **silo**, and application config
and topics use **s3**. The `MINIO_*` variables, the `.minio.sys` folder on disk and
`arn:minio:sqs::…` are Silo's compatibility interface and cannot be renamed.

## Before you start (owner)

1. **Infisical**, project `legohunter.io`, environment **Production**, path `/`:
   - `silo-prod-root`: `{"root_user": "<not minio/admin>", "root_password": "<long random>"}`
   - `silo-prod-ingress`: `{"access_key": "lcms-ingress", "secret_key": "<long random>"}`
     (`access_key` must be exactly `lcms-ingress`)
   - `redpanda-prod-users` already exists; Silo uses its `prodproducer_password`.
2. **Technitium DNS:** `console.silo.prod.internal.legohunter.io` and
   `api.silo.prod.internal.legohunter.io` → `10.0.2.80` (Traefik).

## Commissioning steps

Each step is applied with `lcms-admin`, on the owner's authorization.

| # | Command | Check |
|---|---|---|
| 0 | `kubectl apply --dry-run=server -f 01-… -f 02-… -f 04-…`, then `helm upgrade --install silo-prod <chart> -n silo-prod -f 03-silo-prod-values.yaml --dry-run=server` | Nothing is changed; the server accepts the manifests and the rendered chart |
| 1 | `kubectl apply -f 01-silo-prod-namespace.yaml` | `kubectl get ns silo-prod` |
| 2 | `kubectl apply -f 02-silo-prod-external-secrets.yaml` | All three ExternalSecrets show `SecretSynced`; key names are `rootUser`/`rootPassword`, `secretKey` and `config.env` (check names only) |
| 3 | `../../redpanda/redpanda-prod/05-redpanda-prod-users-and-topics.sh`, then delete the empty old topic: `rpk topic delete prod-minio-s3-events` | `prod-s3-events` exists and `prod-minio-s3-events` is gone |
| 4 | `git clone --depth 1 --branch RELEASE.2026-10-26T00-00-00Z https://github.com/pgsty/silo`, then `helm upgrade --install silo-prod silo/helm/silo -n silo-prod -f 03-silo-prod-values.yaml` | 4 pods Running on 07/08/09/10; 16 PVCs of 75Gi; `mc admin info` shows 16/16 drives online; the post-install job Succeeded; both buckets, the user, the policy and the event rules exist |
| 5 | `kubectl apply -f 04-silo-prod-tls-and-routes.yaml` | The certificate is Ready; the console URL loads with the Let's Encrypt cert; `https://api.silo.prod…/minio/health/live` returns 200 |
| 6 | End-to-end check: as `lcms-ingress`, put a test object in `lego-uploads-prod` under `poc/`, then delete it; read `prod-s3-events` | One `s3:ObjectCreated:Put` event arrives (deletes in the uploads bucket are not subscribed). ingress PROD isn't running yet; when it starts it will log the `poc/` key as not routable |

## Notes

- **Notification queue.** `/silo-notify-queue` is an emptyDir. Events that can't be delivered
  while redpanda-prod is down survive a container restart, but not the pod being moved to another
  node.
- **Growth.** Add a second pool, i.e. another `pools` entry with new servers and drives, at
  about 70% full. Do not enlarge drives.
- **Client.** Use Silo's client image `pgsty/mc` (the binary is `mc`; Silo's docs call it `mcli`).
  The chart's jobs register the target as `mysilo`.
- **Traefik.** Every IngressRoute needs the annotation `kubernetes.io/ingress.class: traefik`.
