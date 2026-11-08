#!/usr/bin/env bash
# Creates the redpanda-dev topics and ACLs lego-data-ingress DEV uses (HOMELAB-57), as named in
# lego-data-ingress src/main/resources/application-dev.yml. dev-s3-events already exists
# (05-dev-s3-events-topic.sh, HOMELAB-54); it is listed again so this script checks the full set.
# Safe to re-run: existing topics are left as they are, and re-creating an ACL is a no-op.
#
# Users (owner decision 2026-11-08): DEV reuses devproducer/devconsumer, the same users as SANDBOX.
# redpanda-dev ACLs are per name (LITERAL), so every topic and consumer group gets its own:
#   devproducer  write, describe on the topic (ingress routes and produces entry events)
#   devconsumer  read, describe on the topic and on <topic>-group
#
# Partitions: 3 each. DEV runs the photo consumer with concurrency 1 (SANDBOX and PROD use 12
# partitions for dev-upload-photo's equivalent because they run 4 consumers).
#
# Run it where kubectl can read Secrets in redpanda-dev and exec into its pods (an admin context):
#   KUBE_CONTEXT=lcms-admin ./06-dev-ingress-topics.sh
# The admin password comes from the hand-made Secret redpanda-dev/redpanda-dev-superusers
# (redpanda-users.admin_password in Infisical is stale, HOMELAB-50) and goes to rpk on stdin only.
set -euo pipefail

NS=redpanda-dev
POD=redpanda-dev-0
CTX=${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"}
PARTITIONS=3
REPLICAS=3

TOPICS=(
  dev-s3-events
  dev-upload-photo
  dev-delete-photo
  dev-upload-bricklink-catalog
  dev-upload-bricklink-category
  dev-upload-rebrickable-catalog
  dev-upload-rebrickable-theme
  dev-photo-upload-entry
  dev-bricklink-catalog-entry
  dev-bricklink-category-entry
  dev-rebrickable-catalog-entry
  dev-rebrickable-theme-entry
)

admin_password() {  # prints the admin password (used only in pipes)
  kubectl $CTX get secret redpanda-dev-superusers -n "$NS" -o "jsonpath={.data.superusers\.txt}" |
    base64 -d | awk -F: '$1 == "admin" {print $2; exit}'
}

rpk_admin() {  # rpk_admin <rpk args...>: rpk in the broker pod as the SASL superuser "admin"
  admin_password | kubectl $CTX exec -i -n "$NS" "$POD" -c redpanda -- bash -c '
    IFS= read -r RPK_PASS; export RPK_PASS
    exec rpk "$@" -X user=admin -X sasl.mechanism=SCRAM-SHA-512' rpk "$@"
}

echo "== topics"
existing=$(rpk_admin topic list | awk 'NR>1 {print $1}')
for topic in "${TOPICS[@]}"; do
  if grep -qx "$topic" <<<"$existing"; then
    echo "topic $topic: exists"
  else
    rpk_admin topic create "$topic" -p "$PARTITIONS" -r "$REPLICAS" >/dev/null
    echo "topic $topic: created ($PARTITIONS partitions)"
  fi
done

echo "== acls"
for topic in "${TOPICS[@]}"; do
  rpk_admin security acl create --allow-principal User:devproducer --operation write,describe --topic "$topic" >/dev/null
  rpk_admin security acl create --allow-principal User:devconsumer --operation read,describe --topic "$topic" >/dev/null
  rpk_admin security acl create --allow-principal User:devconsumer --operation read,describe --group "$topic-group" >/dev/null
done
echo "acls: devproducer write/describe and devconsumer read/describe on ${#TOPICS[@]} topics and their -group groups"

echo "== check"
rpk_admin topic list | awk 'NR==1 || $1 ~ /^dev-/'
