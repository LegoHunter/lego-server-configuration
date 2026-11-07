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
- **Users, topics and ACLs were made by hand with `rpk`.** Nothing records them except the broker;
  the commands in `../README.md` are historical and do not match the topics ingress uses today.
- **The console runs `:latest`** (v3.13.1 on 2026-11-07).
- **The external-dns annotations do nothing.** No external-dns is deployed; DNS records are added
  by hand in Technitium (`redpanda-dev-0/1/2.dev.internal.legohunter.io` → 10.0.2.101/.102/.100).
