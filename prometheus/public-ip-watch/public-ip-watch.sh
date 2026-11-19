#!/bin/sh
# Public IP watch (HOMELAB-6). Runs as the CronJob monitoring/public-ip-watch every 15 minutes.
#
# The BrickLink API token is bound to the home's public IP address, and Xfinity changes that
# address from time to time. After a change BrickLink refuses every API call until a token is
# registered for the new address. This script tells the owner within one run.
#
# Each run:
#   1. asks two lookup services for the public IPv4 address and goes on only when both give the
#      same valid address (one failing or disagreeing service never raises an alarm);
#   2. compares it with the last known address, kept in the ConfigMap public-ip-watch-state
#      (mounted read-only at $STATE_DIR; updated through the Kubernetes API);
#   3. on a change, sends a Pushover message and only then stores the new address, so a failed
#      send is tried again on the next run;
#   4. pushes the current address and a last-success timestamp to the Pushgateway. An alert rule
#      on that timestamp fires when the watch itself stops working.
#
# Exit code 0: the run completed. 1: a lookup, the message, the state update or the metric push
# failed; the next run starts over.
#
# Environment (set by the CronJob):
#   PUSHOVER_APP_TOKEN, PUSHOVER_USER_KEY   Pushover credentials (from Secret alertmanager-pushover)
#   NAMESPACE                               the pod's namespace
#   STATE_CONFIGMAP                         name of the state ConfigMap
#   STATE_DIR                               where that ConfigMap is mounted
#   PUSHGATEWAY_URL                         base URL of the Pushgateway
#   LOOKUP_URL_1, LOOKUP_URL_2              optional: the two lookup services
set -u

LOOKUP_URL_1="${LOOKUP_URL_1:-https://api.ipify.org}"
LOOKUP_URL_2="${LOOKUP_URL_2:-https://ifconfig.me/ip}"
SERVICE_ACCOUNT_DIR=/var/run/secrets/kubernetes.io/serviceaccount

log() {
    echo "public_ip_watch.$1"
}

# Prints the address a lookup service reports, or nothing when the call fails.
lookup() {
    curl -4 -sS --fail --max-time 20 "$1" 2>/dev/null | tr -d ' \r\n'
}

is_ipv4() {
    echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

state() {
    cat "$STATE_DIR/$1" 2>/dev/null || true
}

# Sends one Pushover message. The credentials go to curl on standard input, not on the command line.
notify() {
    title="$1"
    message="$2"
    priority="$3"
    {
        printf 'form-string = "token=%s"\n' "$PUSHOVER_APP_TOKEN"
        printf 'form-string = "user=%s"\n' "$PUSHOVER_USER_KEY"
    } | curl -sS --fail --max-time 30 -o /dev/null -K - \
        --form-string "title=$title" \
        --form-string "message=$message" \
        --form-string "priority=$priority" \
        https://api.pushover.net/1/messages.json
}

# Stores the address in the state ConfigMap.
store_state() {
    {
        printf 'header = "Authorization: Bearer %s"\n' "$(cat "$SERVICE_ACCOUNT_DIR/token")"
    } | curl -sS --fail --max-time 30 -o /dev/null -K - \
        --cacert "$SERVICE_ACCOUNT_DIR/ca.crt" \
        -X PATCH -H 'Content-Type: application/merge-patch+json' \
        -d "{\"data\":{\"last_ip\":\"$1\",\"previous_ip\":\"$2\",\"changed_at\":\"$3\"}}" \
        "https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE/configmaps/$STATE_CONFIGMAP"
}

push_metrics() {
    cat <<METRICS | curl -sS --fail --max-time 30 -o /dev/null -X PUT --data-binary @- "$PUSHGATEWAY_URL/metrics/job/public_ip_watch"
# HELP homelab_public_ip_info The home's public IPv4 address, in the ip label.
# TYPE homelab_public_ip_info gauge
homelab_public_ip_info{ip="$1"} 1
# HELP homelab_public_ip_changed_timestamp_seconds When the watch last saw the public address change (epoch seconds); 0 until the first change.
# TYPE homelab_public_ip_changed_timestamp_seconds gauge
homelab_public_ip_changed_timestamp_seconds $2
# HELP homelab_public_ip_watch_last_success_timestamp_seconds When the public IP watch last completed a run (epoch seconds).
# TYPE homelab_public_ip_watch_last_success_timestamp_seconds gauge
homelab_public_ip_watch_last_success_timestamp_seconds $3
METRICS
}

first="$(lookup "$LOOKUP_URL_1")"
second="$(lookup "$LOOKUP_URL_2")"
if ! is_ipv4 "$first" || ! is_ipv4 "$second"; then
    log "lookup_failed first=${first:-none} second=${second:-none}"
    exit 1
fi
if [ "$first" != "$second" ]; then
    log "lookup_disagreement first=$first second=$second"
    exit 1
fi

current="$first"
last="$(state last_ip)"
changed_at="$(state changed_at)"
now="$(date +%s)"
when="$(date -u '+%Y-%m-%d %H:%M UTC')"

if [ -z "$last" ]; then
    # First run, or the state was cleared: remember the address and say the watch is working.
    if ! notify "Public IP watch started" "The public IP watch is running. Current address: $current ($when)." 0; then
        log "notification_failed reason=first_run current=$current"
        exit 1
    fi
    changed_at=0
    if ! store_state "$current" "" "$changed_at"; then
        log "state_update_failed current=$current"
        exit 1
    fi
    log "started current=$current"
elif [ "$current" != "$last" ]; then
    message="The home public IP changed from $last to $current ($when).
The BrickLink API token is bound to the old address, so BrickLink now refuses every API call.
1. On BrickLink, register an API access token for $current.
2. Put the new token in bricklink-client-api-keys.yml in Infisical (Global) and in D:\\dev\\config.
3. Restart lego-data-ingress and bricklink-web-gateway in each environment.
Runbook: lego-server-configuration/prometheus/README.md"
    if ! notify "Public IP changed: $last -> $current" "$message" 1; then
        log "notification_failed previous=$last current=$current"
        exit 1
    fi
    changed_at="$now"
    if ! store_state "$current" "$last" "$changed_at"; then
        log "state_update_failed previous=$last current=$current"
        exit 1
    fi
    log "changed previous=$last current=$current"
else
    log "unchanged current=$current"
fi

if ! push_metrics "$current" "${changed_at:-0}" "$now"; then
    log "metric_push_failed current=$current"
    exit 1
fi
