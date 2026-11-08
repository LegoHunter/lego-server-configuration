#!/usr/bin/env bash
# Creates the redpanda-dev topic dev-s3-events and its ACLs (HOMELAB-54): silo-dev's DEV bucket
# notifications publish there as devproducer, and lego-data-ingress DEV will consume it as
# devconsumer in group dev-s3-events-group (wired up by HOMELAB-57).
# Safe to re-run: an existing topic is left as it is, and re-creating an ACL is a no-op.
#
# redpanda-dev ACLs are per name (LITERAL), like the existing sandbox-* ones (README.md).
#
# Run it where kubectl can read Secrets in redpanda-dev and exec into its pods (an admin context):
#   KUBE_CONTEXT=lcms-admin ./05-dev-s3-events-topic.sh
#
# The admin password comes from the hand-made Secret redpanda-dev/redpanda-dev-superusers
# (superusers.txt, one line "admin:<password>:<mechanism>"). redpanda-users.admin_password in
# Infisical is stale and Kafka rejects it (README.md, HOMELAB-50). The password goes to rpk inside
# the broker pod on stdin, so it never appears in command lines, shell history or this output.
set -euo pipefail

NS=redpanda-dev
POD=redpanda-dev-0
CTX=${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"}
TOPIC=dev-s3-events
PARTITIONS=3                     # the same as sandbox-s3-events
REPLICAS=3

admin_password() {  # prints the admin password (used only in pipes)
  kubectl $CTX get secret redpanda-dev-superusers -n "$NS" -o "jsonpath={.data.superusers\.txt}" |
    base64 -d | awk -F: '$1 == "admin" {print $2; exit}'
}

rpk_admin() {  # rpk_admin <rpk args...>: rpk in the broker pod as the SASL superuser "admin"
  admin_password | kubectl $CTX exec -i -n "$NS" "$POD" -c redpanda -- bash -c '
    IFS= read -r RPK_PASS; export RPK_PASS
    exec rpk "$@" -X user=admin -X sasl.mechanism=SCRAM-SHA-512' rpk "$@"
}

echo "== topic"
if rpk_admin topic list | awk 'NR>1 {print $1}' | grep -qx "$TOPIC"; then
  echo "topic $TOPIC: exists"
else
  rpk_admin topic create "$TOPIC" -p "$PARTITIONS" -r "$REPLICAS" >/dev/null
  echo "topic $TOPIC: created ($PARTITIONS partitions)"
fi

echo "== acls"
rpk_admin security acl create --allow-principal User:devproducer --operation write,describe --topic "$TOPIC" >/dev/null
rpk_admin security acl create --allow-principal User:devconsumer --operation read,describe --topic "$TOPIC" >/dev/null
rpk_admin security acl create --allow-principal User:devconsumer --operation read,describe --group "$TOPIC-group" >/dev/null
echo "acls: devproducer write/describe on $TOPIC; devconsumer read/describe on $TOPIC and $TOPIC-group"

echo "== check"
rpk_admin topic describe "$TOPIC"
rpk_admin security acl list --topic "$TOPIC"
