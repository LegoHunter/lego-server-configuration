# redpanda-dev (as deployed)

These are the files that built the live `redpanda-dev` cluster, copied on 2026-11-07 from
`~sysadmin/redpanda/redpanda-dev/` on rasppi5-01 (HOMELAB-47). Until then they existed only there.
`redpanda-dev-cluster.yaml` matches the live `Redpanda` CR.

SANDBOX and DEV both use this cluster, with `sandbox-*` and `dev-*` topics. PROD has its own
cluster in `../redpanda-prod/`.

Known differences from what is deployed, and known issues:

- **Console password removed.** `redpanda-dev-console/redpanda-dev-console-configmap.yaml` held the
  admin password in plain text. The copy here has `<REMOVED - see README>`, so it must not be
  applied as is. The live ConfigMap still holds the password; fix it the way PROD does
  (the `KAFKA_SASL_PASSWORD` environment variable from the `redpanda-users` Secret).
- **The superusers Secret was made by hand.** `redpanda-dev-superusers` came from a
  `superusers.txt` file on rasppi5-01; no manifest creates it.
- **Users were made by hand with `rpk`,** and so were the topics and ACLs until scripts took over:
  `05-dev-s3-events-topic.sh` and `06-dev-ingress-topics.sh` for DEV, `07-sandbox-ingress-topics.sh`
  for SANDBOX (HOMELAB-178). The commands in `../README.md` are historical and do not match the
  topics ingress uses today.
- **The console runs `:latest`** (v3.13.1 on 2026-11-07).
- **The external-dns annotations do nothing.** No external-dns is deployed; DNS records are added
  by hand in Technitium (`redpanda-dev-0/1/2.dev.internal.legohunter.io` → 10.0.2.101/.102/.100).

## SANDBOX and DEV topics, users and ACLs (as of 2026-11-26)

**To add a topic:** add it to `07-sandbox-ingress-topics.sh` (SANDBOX) and `06-dev-ingress-topics.sh`
(DEV), and to `../redpanda-prod/05-redpanda-prod-users-and-topics.sh` (PROD), then run the script
with an admin context: `KUBE_CONTEXT=lcms-admin ./07-sandbox-ingress-topics.sh`. Each script is
safe to re-run: it leaves existing topics as they are and re-creating an ACL changes nothing.

- **Users:** `admin` (superuser), `devproducer`, `devconsumer` and `kubernetes-controller`.
  - The `admin` password comes from `superusers.txt` / `redpanda-dev-superusers`.
  - `redpanda-users.admin_password` in Infisical is **stale** and Kafka rejects it (HOMELAB-50).
- **ACLs are per name (`LITERAL`), not prefixed.** Every new topic needs its own ACLs:
  - `devproducer`: write and describe on the topic;
  - `devconsumer`: read and describe on the topic and on `<topic>-group`.
- **Topics:**
  - `sandbox-s3-events`: 3 partitions. silo-dev's SANDBOX bucket events go here (minio-dev's until
    2026-11-08, HOMELAB-54); ingress consumes it as
    `sandbox-s3-events-group`.
  - `sandbox-upload-*`, `sandbox-delete-photo` and `sandbox-*-entry`: the routed topics. They were
    made by hand; `07-sandbox-ingress-topics.sh` now lists all of them with their partition counts.
  - `sandbox-upload-lego-wooden-toys-catalog` and `sandbox-lego-wooden-toys-catalog-entry`
    (HOMELAB-178, 3 partitions each): the load of LEGO's wooden toys catalog. The first receives the
    routed bucket event for a capture file, the second carries one message per catalog entry. DEV
    and PROD have the same pair with their own prefix.
  - `sandbox-photo-upload-entry` is named in ingress's `application-sandbox.yml` but the broker does
    not have it (2026-11-26). DEV has `dev-photo-upload-entry`. Not created here; see the note in
    `07-sandbox-ingress-topics.sh`.
  - `dev-s3-events` (HOMELAB-54, `05-dev-s3-events-topic.sh`) and the `dev-*` application topics
    (HOMELAB-57, `06-dev-ingress-topics.sh`), 3 partitions each.
  - `dev-test-topic`: a leftover test topic. Its consumer group has no ACL.
- **Retention:** the cluster default, 7 days.

**History**
- 2026-11-26 (HOMELAB-178): the two wooden toys catalog topics and their ACLs were created in
  SANDBOX and DEV with the scripts. Before the run, every existing `sandbox-*` topic already had
  exactly the ACLs `07-sandbox-ingress-topics.sh` creates, so the run changed nothing for them.
- 2026-11-08 (HOMELAB-53): `sandbox-minio-s3-events` was renamed `sandbox-s3-events`. The new topic
  and its ACLs were created, minio-dev was switched over, and then the old topic, its group and its
  6 ACLs were deleted.

Creating a topic, e.g.:

```bash
# in redpanda-dev-0 (container redpanda); the admin password goes in on stdin as RPK_PASS
rpk topic create <topic> -p 3 -r 3 -X user=admin -X sasl.mechanism=SCRAM-SHA-512
rpk security acl create --allow-principal User:devproducer --operation write,describe --topic <topic> ...
rpk security acl create --allow-principal User:devconsumer --operation read,describe --topic <topic> ...
rpk security acl create --allow-principal User:devconsumer --operation read,describe --group <topic>-group ...
```
