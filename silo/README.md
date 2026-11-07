# Silo (S3 object storage)

[Silo](https://github.com/pgsty/silo) is a maintained fork of MinIO (AGPL-3.0, published by
Pigsty). It replaces MinIO, whose open-source server and operator were archived upstream in 2026.
The decision, the evaluation of the alternatives (RustFS, SeaweedFS, Garage, Ceph) and the proof
of concept are in HOMELAB-48.

| Folder | What |
|---|---|
| `silo-prod/` | The dedicated PROD store (HOMELAB-48) |
| `silo-dev/` | SANDBOX and DEV, replacing `minio-dev` (HOMELAB-54); to come |

**Naming rule:** infrastructure is called **silo** (`silo-dev`, `silo-prod`,
`console.silo.<env>.internal.legohunter.io`). Application config, classes and Kafka topics use the
neutral name **s3** (`<env>-s3-events`, `lego.s3.*`). lego-data-ingress keeps the MinIO Java client
library (`io.minio:minio`), which is still maintained.

`../minio/` documents the old minio-dev install. It goes away with HOMELAB-54 and HOMELAB-51.
