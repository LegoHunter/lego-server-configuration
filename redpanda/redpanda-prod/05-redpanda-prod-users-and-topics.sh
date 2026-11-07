#!/usr/bin/env bash
# Creates the redpanda-prod Kafka users, topics and ACLs for lego-data-ingress PROD (HOMELAB-47).
# Safe to re-run: existing users and topics are left as they are, and re-creating an ACL is a no-op.
#
# Run it on rasppi5-01 (or anywhere kubectl reaches the cluster with rights to read Secrets in
# redpanda-prod and exec into its pods):
#   ./05-redpanda-prod-users-and-topics.sh
#
# Passwords come from the Secret redpanda-prod/redpanda-users (ExternalSecrets, from Infisical
# Production). They are passed to rpk inside the broker pod on stdin, so they never appear in
# command lines, shell history or this script's output.
#
# Topics mirror lego-data-ingress's SANDBOX profile (application-sandbox.yml), with the
# sandbox- prefix replaced by prod-. Consumer groups are <topic>-group.
set -euo pipefail

NS=redpanda-prod
POD=redpanda-prod-0
CTX=${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"}
RETENTION_MS=2592000000          # 30 days (also the cluster default)
REPLICAS=3

# topic:partitions. upload-photo has 12 partitions, as in SANDBOX, so the four photo consumers
# can work in parallel.
TOPICS=(
  prod-minio-s3-events:3
  prod-upload-photo:12
  prod-delete-photo:3
  prod-upload-bricklink-catalog:3
  prod-upload-bricklink-category:3
  prod-upload-rebrickable-catalog:3
  prod-upload-rebrickable-theme:3
  prod-photo-upload-entry:3
  prod-bricklink-catalog-entry:3
  prod-bricklink-category-entry:3
  prod-rebrickable-catalog-entry:3
  prod-rebrickable-theme-entry:3
)

secret() {  # secret <key>: prints one decoded value from redpanda-users (used only in pipes)
  kubectl $CTX get secret redpanda-users -n "$NS" -o "jsonpath={.data.$1}" | base64 -d
}

# rpk_admin <rpk args...>: runs rpk in the broker pod as the SASL superuser "admin". The password
# goes in on stdin.
rpk_admin() {
  secret admin_password | kubectl $CTX exec -i -n "$NS" "$POD" -c redpanda -- bash -c '
    IFS= read -r RPK_PASS; export RPK_PASS
    exec rpk "$@" -X user=admin -X sasl.mechanism=SCRAM-SHA-512' rpk "$@"
}

# create_user <name> <password-key>: creates the user if it does not exist yet.
create_user() {
  local name=$1 key=$2
  if rpk_admin security user list | awk 'NR>1 {print $1}' | grep -qx "$name"; then
    echo "user $name: exists"
  else
    { secret admin_password; echo; secret "$key"; echo; } |
      kubectl $CTX exec -i -n "$NS" "$POD" -c redpanda -- bash -c '
        IFS= read -r RPK_PASS; export RPK_PASS
        IFS= read -r NEW_PASS
        rpk security user create "$1" --new-password "$NEW_PASS" --mechanism SCRAM-SHA-512 \
          -X user=admin -X sasl.mechanism=SCRAM-SHA-512 >/dev/null' rpk "$name"
    echo "user $name: created"
  fi
}

echo "== users"
create_user prodproducer prodproducer_password
create_user prodconsumer prodconsumer_password

echo "== topics"
existing=$(rpk_admin topic list | awk 'NR>1 {print $1}')
for entry in "${TOPICS[@]}"; do
  topic=${entry%%:*} partitions=${entry##*:}
  if grep -qx "$topic" <<<"$existing"; then
    echo "topic $topic: exists"
  else
    rpk_admin topic create "$topic" -p "$partitions" -r "$REPLICAS" -c retention.ms="$RETENTION_MS" >/dev/null
    echo "topic $topic: created ($partitions partitions)"
  fi
done

echo "== acls"
# Prefixed ACLs cover every prod- topic and prod-...-group consumer group, including topics added later.
# lego-data-ingress produces (MinIO events are routed onto the upload and entry topics) as
# prodproducer, and consumes as prodconsumer. MinIO's bucket notifications also produce, as
# prodproducer.
rpk_admin security acl create --allow-principal User:prodproducer \
  --operation write,describe --topic prod- --resource-pattern-type prefixed >/dev/null
rpk_admin security acl create --allow-principal User:prodconsumer \
  --operation read,describe --topic prod- --resource-pattern-type prefixed >/dev/null
rpk_admin security acl create --allow-principal User:prodconsumer \
  --operation read,describe --group prod- --resource-pattern-type prefixed >/dev/null
echo "acls: prodproducer write/describe on topics prod-*; prodconsumer read/describe on topics and groups prod-*"

echo "== check"
rpk_admin security user list
rpk_admin topic list
rpk_admin security acl list
