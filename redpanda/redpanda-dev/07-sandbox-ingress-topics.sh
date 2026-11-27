#!/usr/bin/env bash
# Creates the redpanda-dev topics and ACLs lego-data-ingress SANDBOX uses, as named in
# lego-data-ingress src/main/resources/application-sandbox.yml (HOMELAB-178).
#
# Until this script the sandbox-* topics were made by hand with rpk and nothing recorded how. The
# list below is what the broker held on 2026-11-26, with each topic's partition count, plus the two
# topics of LEGO's wooden toys catalog load.
# Safe to re-run: existing topics are left as they are, and re-creating an ACL is a no-op. On
# 2026-11-26 every existing sandbox-* topic already had exactly the ACLs this script creates, so a
# run changed nothing for them.
#
# Users: SANDBOX and DEV share devproducer and devconsumer (owner decision 2026-11-08).
# redpanda-dev ACLs are per name (LITERAL), so every topic and consumer group gets its own:
#   devproducer  write, describe on the topic (ingress routes and produces entry events; silo-dev
#                publishes bucket events onto sandbox-s3-events)
#   devconsumer  read, describe on the topic and on <topic>-group
#
# Not in the list: sandbox-photo-upload-entry. application-sandbox.yml names it, but the broker did
# not have it on 2026-11-26, and this script does not create what SANDBOX has been running without.
# Add it here if it is found to be needed.
#
# Run it where kubectl can read Secrets in redpanda-dev and exec into its pods (an admin context):
#   KUBE_CONTEXT=lcms-admin ./07-sandbox-ingress-topics.sh
# The admin password comes from the hand-made Secret redpanda-dev/redpanda-dev-superusers
# (redpanda-users.admin_password in Infisical is stale, HOMELAB-50) and goes to rpk on stdin only.
set -euo pipefail

NS=redpanda-dev
POD=redpanda-dev-0
CTX=${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"}
REPLICAS=3

# topic:partitions
TOPICS=(
  sandbox-s3-events:3
  sandbox-upload-photo:12
  sandbox-delete-photo:12
  sandbox-upload-bricklink-catalog:3
  sandbox-upload-bricklink-category:3
  sandbox-upload-rebrickable-catalog:12
  sandbox-upload-rebrickable-theme:12
  sandbox-bricklink-catalog-entry:12
  sandbox-bricklink-category-entry:12
  sandbox-rebrickable-catalog-entry:12
  sandbox-rebrickable-theme-entry:12
  # LEGO's wooden toys catalog load (HOMELAB-178): the routed capture file event, and one message per entry.
  sandbox-upload-lego-wooden-toys-catalog:3
  sandbox-lego-wooden-toys-catalog-entry:3
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
for entry in "${TOPICS[@]}"; do
  topic=${entry%%:*} partitions=${entry##*:}
  if grep -qx "$topic" <<<"$existing"; then
    echo "topic $topic: exists"
  else
    rpk_admin topic create "$topic" -p "$partitions" -r "$REPLICAS" >/dev/null
    echo "topic $topic: created ($partitions partitions)"
  fi
done

echo "== acls"
for entry in "${TOPICS[@]}"; do
  topic=${entry%%:*}
  rpk_admin security acl create --allow-principal User:devproducer --operation write,describe --topic "$topic" >/dev/null
  rpk_admin security acl create --allow-principal User:devconsumer --operation read,describe --topic "$topic" >/dev/null
  rpk_admin security acl create --allow-principal User:devconsumer --operation read,describe --group "$topic-group" >/dev/null
done
echo "acls: devproducer write/describe and devconsumer read/describe on ${#TOPICS[@]} topics and their -group groups"

echo "== check"
rpk_admin topic list | awk 'NR==1 || $1 ~ /^sandbox-/'
