## Grafana

Grafana runs in the namespace `monitoring` as the Helm release `grafana` (chart
`grafana-community/grafana` 10.5.15, Grafana 12.3.1) at
`https://console.grafana.internal.legohunter.io`. Files are in `grafana/`:

| File | What it is |
|---|---|
| `grafana-community-values.yaml` | The Helm values. No secret in it. |
| `grafana-admin-external-secret.yaml` | The admin sign-in, from Infisical Global into `monitoring/grafana-admin`. |
| `grafana-tls.yaml` | The Let's Encrypt certificate. |
| `grafana-ingressroute.yaml` | The Traefik route. |
| `dashboards/` | Dashboard JSON, imported by hand (see below). |

### What is kept where

Grafana's database (`/var/lib/grafana/grafana.db`: users, passwords, dashboards made or imported in
the UI, preferences) is on the volume `monitoring/grafana` (5 Gi, StorageClass
`topolvm-provisioner`), so it survives a pod restart (HOMELAB-75). Until 2026-11-20 it was in an
emptyDir and every restart wiped it. The two data sources (Prometheus, Loki) are provisioned from
the Helm values.

The volume is local to one node, so Grafana always starts on that node. If that node is lost, the
database is lost with it: keep dashboards worth keeping as JSON in `dashboards/`.

Alert rules are not in Grafana. They are Prometheus rules, delivered by Alertmanager; see
`../prometheus/README.md`.

### The admin password

Grafana reads the admin user and password from the Secret `grafana-admin` **only when it first
creates its database**. After that the password lives in the database. Changing the value in
Infisical alone does not change the login.

To change the password: change it in Grafana (profile, Change password), then put the new one in
the Infisical Global secret `grafana-admin`, so a fresh install starts with it. If the password is
lost, reset it in the pod (it asks nothing; replace the placeholder):

```shell
kubectl exec -n monitoring deploy/grafana -c grafana -- grafana cli admin reset-admin-password '<new password>'
```

### Install

One-time (owner): add the Infisical Global secret `grafana-admin` with the value
`{"admin_user": "admin", "admin_password": "<password>"}`.

```shell
kubectl apply -f grafana/grafana-admin-external-secret.yaml
kubectl get externalsecret grafana-admin -n monitoring        # expect: SecretSynced

helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update
helm upgrade --install grafana grafana-community/grafana -n monitoring --version 10.5.15   -f grafana/grafana-community-values.yaml

kubectl apply -f grafana/grafana-tls.yaml
kubectl apply -f grafana/grafana-ingressroute.yaml
```

### Upgrade

```shell
helm upgrade grafana grafana-community/grafana -n monitoring --version 10.5.15   -f grafana/grafana-community-values.yaml
```

An upgrade stops the old pod before starting the new one (strategy `Recreate`), so Grafana is away
for about a minute.

### Uninstall

`helm delete grafana -n monitoring` removes the release **and the volume with the database**. Copy
`grafana.db` out of the pod first if it is to be kept.

### Dashboards

Dashboard JSON lives in `grafana/dashboards/` and is imported by hand (Dashboards > New > Import).
No provisioning config loads it.

| File | Dashboard | What it covers |
| --- | --- | --- |
| `lego-data-ingress.json` | Lego Data Ingress - Pipelines | lego-data-ingress service health, photo ingestion, Flickr sync, HTTP/Kafka, the Pricing Plane (including pricing data-quality gaps), the Reprice job (latest decision per listing with its guard outcome, and its sync hand-offs), and the marketplace reconciliation and lower-environment lot audit |

Import over the existing dashboard: the file keeps its original `uid`
(`lego-data-ingress-photo-pipeline`, from before the file was renamed), so Grafana replaces the
dashboard in place instead of creating a copy. Choose the Prometheus data source for
`DS_PROMETHEUS` and the Loki data source for `DS_LOKI` when asked. The **Reprice** row's two tables
read the RepriceJob log lines from Loki; the rest of the dashboard is Prometheus.

The **Namespace** dropdown switches it between SANDBOX (`services-sandbox`, the default) and DEV
(`services-dev`). Service is fixed to `lego-data-ingress`.
