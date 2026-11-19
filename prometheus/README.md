# Prometheus, alerts and the public IP watch

Prometheus runs in the namespace `monitoring` as the Helm release `prometheus`
(chart `prometheus-community/prometheus` 29.1.0: Prometheus server, Alertmanager, Pushgateway,
node-exporter and kube-state-metrics). It is not the Prometheus operator, so there are no
`PrometheusRule` or `ServiceMonitor` objects; rules and scrape jobs are Helm values.

| File | What it is |
|---|---|
| `prometheus-values.yaml` | The base values of the release, recovered from the cluster on 2026-11-19. See [Base values](#base-values). |
| `prometheus-alerting-values.yaml` | Every alert rule, and Alertmanager's delivery to Pushover. |
| `01-pushover-external-secret.yaml` | The Pushover credentials, from Infisical Global into `monitoring/alertmanager-pushover`. |
| `public-ip-watch/` | The CronJob that reports a change of the home's public IP address. |

## How alerts work

**This folder is the home of alert rules** (owner decision 2026-11-19, HOMELAB-6). Prometheus
evaluates the rules in `prometheus-alerting-values.yaml` every minute. A rule that stays true for
its `for:` time fires, and Alertmanager sends it to the owner's phone through Pushover. Alertmanager
sends a second message when the problem clears, and repeats a problem that is still there every
12 hours. Grafana alerting is not used, so no alert depends on Grafana's storage.

To add an alert, add a rule to `prometheus-alerting-values.yaml` and run the Helm upgrade below.

| Alert | Fires when | What to do |
|---|---|---|
| `BricklinkApiCredentialsRejected` | BrickLink has refused the API token (401 or 403) for 15 minutes | [The public IP changed](#the-public-ip-changed), or the token was revoked |
| `PublicIpWatchNotRunning` | The public IP watch has not completed a run for over an hour | [The watch is not running](#the-watch-is-not-running) |

`BricklinkApiCredentialsRejected` reads the counter
`bricklink_api_credentials_rejected_total{source}`, which lego-data-ingress exports for each of its
BrickLink jobs and bricklink-web-gateway for its stockroom check. Those jobs treat a refused token
as an outage and only log a warning, so this alert is how the owner finds out.

## The public IP watch

The BrickLink API token is bound to the home's public IP address. Xfinity changes that address from
time to time, and from then on BrickLink refuses every API call (`401 TOKEN_IP_MISMATCHED`) until a
token is registered for the new address. In October 2026 this went unnoticed for three weeks.

The CronJob `monitoring/public-ip-watch` runs every 15 minutes:

1. It asks two lookup services (`api.ipify.org`, `ifconfig.me`) for the public address and goes on
   only when both give the same address. One service failing or disagreeing raises no alarm.
2. It compares the address with the last known one, which it keeps in the ConfigMap
   `public-ip-watch-state`.
3. On a change it sends a Pushover message with the old and new address and the steps to take, and
   then stores the new address. If the message cannot be sent, the next run tries again.
4. It pushes the address to the Pushgateway, so it is visible in Prometheus and Grafana:
   - `homelab_public_ip_info{ip="…"}`: the current address
   - `homelab_public_ip_changed_timestamp_seconds`: when the last change was seen (0 until the first)
   - `homelab_public_ip_watch_last_success_timestamp_seconds`: when the watch last completed a run

The watch sends its own message and does not go through Alertmanager, so it reports the old and the
new address in one message.

**Known gap (accepted by the owner):** the watch runs in the cluster, so it sees nothing while the
cluster is down. A change during an outage is reported on the first run after the cluster is back.
`BricklinkApiCredentialsRejected` is the second net.

## Runbook

### The public IP changed

1. On BrickLink's API token page, register an API access token for the new address. The new
   address is in the Pushover message and in `homelab_public_ip_info`.
2. Put the new token value and token secret in `bricklink-client-api-keys.yml` in Infisical,
   environment **Global**. Every environment reads that one copy.
3. Put the same values in the local copy under `D:\dev\config`.
4. Wait a minute for External Secrets to sync, then restart the services that read the file at
   startup, in each environment that runs them:
   ```
   kubectl rollout restart deployment/lego-data-ingress deployment/bricklink-web-gateway -n services-sandbox
   kubectl rollout restart deployment/lego-data-ingress deployment/bricklink-web-gateway -n services-dev
   ```
5. Check: the next BrickLink order sync run is `NO_WORK` or `SUCCEEDED`, and
   `BricklinkApiCredentialsRejected` resolves (a "Resolved" message arrives).
6. Remove the token for the old address on BrickLink.

### The watch is not running

```
kubectl get cronjob,jobs -n monitoring | grep public-ip-watch
kubectl logs -n monitoring job/<the latest public-ip-watch job>
```

| Log line | Meaning |
|---|---|
| `lookup_failed`, `lookup_disagreement` | A lookup service is down or the two disagree. Usually passes on its own. If it lasts, set `LOOKUP_URL_1` or `LOOKUP_URL_2` on the CronJob to another service that answers with the bare address. |
| `notification_failed` | Pushover refused the message or could not be reached. Check the Secret `alertmanager-pushover` is synced and the Pushover application still exists. |
| `state_update_failed` | The job could not update `public-ip-watch-state`. Check the Role and RoleBinding `public-ip-watch`. |
| `metric_push_failed` | The Pushgateway is down. |

## Install

### One-time setup (owner)

1. Create a Pushover account and install the app on the phone. Note the **user key**.
2. In Pushover, create an application (for example "LegoHunter Homelab"). Note its **API token**.
3. In Infisical, environment **Global**, add the secret `pushover` with the value
   `{"app_token": "<API token>", "user_key": "<user key>"}`.

### Deploy

```
# 1. The Pushover Secret. Wait for SecretSynced.
kubectl apply -f prometheus/01-pushover-external-secret.yaml
kubectl get externalsecret alertmanager-pushover -n monitoring

# 2. The public IP watch.
kubectl apply -k prometheus/public-ip-watch

# 3. Alert rules and Alertmanager.
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade prometheus prometheus-community/prometheus -n monitoring --version 29.1.0 \
  -f prometheus/prometheus-values.yaml -f prometheus/prometheus-alerting-values.yaml
```

The first run of the watch sends "Public IP watch started" with the current address. That message
confirms the Pushover credentials work.

### Test

**A change of address.** Give the watch a wrong last address and run it once:

```
kubectl patch configmap public-ip-watch-state -n monitoring --type merge -p '{"data":{"last_ip":"192.0.2.1"}}'
kubectl create job --from=cronjob/public-ip-watch public-ip-watch-test -n monitoring
kubectl logs -n monitoring job/public-ip-watch-test      # expect: public_ip_watch.changed previous=192.0.2.1 current=…
kubectl delete job public-ip-watch-test -n monitoring
```

Expect a Pushover message "Public IP changed: 192.0.2.1 -> …". The run stores the real address
again. Run it a second time: the log says `unchanged` and no message arrives.

**Delivery through Alertmanager.** Send a test alert by hand; it clears itself after three minutes:

```
kubectl port-forward -n monitoring svc/prometheus-alertmanager 9093:9093
curl -H 'Content-Type: application/json' http://127.0.0.1:9093/api/v2/alerts -d '[{
  "labels": {"alertname": "AlertDeliveryTest", "severity": "warning"},
  "annotations": {"summary": "Alert delivery test", "description": "Test alert sent by hand. No action needed."},
  "endsAt": "<three minutes from now, e.g. 2026-11-19T22:15:00Z>"}]'
```

Expect a Pushover message "Alert delivery test" within a minute and "Resolved: Alert delivery test"
a few minutes after `endsAt`.

**The rules.** The Prometheus Alerts page lists `BricklinkApiCredentialsRejected` and
`PublicIpWatchNotRunning` as inactive. The first one fires for real only when BrickLink refuses the
token; do not break the token to test it.

## Base values

`prometheus-values.yaml` holds the values the release is deployed with. It was recovered on
2026-11-19 with `helm get values prometheus -n monitoring -o yaml`, and `helm template` of it matched
the live objects exactly before the alerting values were added.

**Four keys in it do nothing.** `sandboxalertmanager`, `pushgateway`, `nodeExporter` and
`kubeStateMetrics` are set to `enabled: false`, but the chart does not know those names (its keys are
`alertmanager`, `prometheus-pushgateway`, `prometheus-node-exporter` and `kube-state-metrics`). So
Alertmanager, the Pushgateway, node-exporter and kube-state-metrics all run, and the alerts and the
public IP watch depend on the first two. The keys are kept as recovered; do not "fix" them to the
real names, which would switch those components off.

The older copy on rasppi5-01 (`~/prometheus/values-prometheus.yaml`) is superseded by this file.
