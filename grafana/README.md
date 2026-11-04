## Grafana

### Grafana Installation

Includes Loki and prometheus datasources in the yaml

```shell
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update

helm install grafana grafana-community/grafana -f grafana-community-values.yml -n monitoring
```

### Grafana upgrade

`helm upgrade grafana grafana-community/grafana -f grafana-community-values.yml -n monitoring`

### Grafana uninstall

`helm delete grafana -n monitoring`



### Deprecated 

When setting up grafana datasource, add header:

* URL: `http://loki-gateway:3100`
* HTTP Header Name: `X-Scope-OrgID`
* HTTP Header Value: `legohunter.io
*

### Grafana Installation

```
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install grafana grafana/grafana -n monitoring -f .\grafana-values.yaml
```

Apply TLS, Load Balancer, and IngressRoute

```shell
kubectl apply -f grafana-tls.yaml -n monitoring
kubectl apply -f grafana-loadbalancer.yaml -n monitoring
kubectl apply -f grafana-ingressroute.yaml -n monitoring
```

* Uninstall

```
helm uninstall grafana -n monitoring
```


### Dashboards

Dashboard JSON lives in `grafana/dashboards/` and is imported by hand (Dashboards > New > Import).
No provisioning config loads it.

| File | Dashboard | What it covers |
| --- | --- | --- |
| `lego-data-ingress.json` | Lego Data Ingress - Pipelines | lego-data-ingress service health, photo ingestion, Flickr sync, HTTP/Kafka, the Pricing Plane, and the marketplace reconciliation and lower-environment lot audit |

Import over the existing dashboard: the file keeps its original `uid`
(`lego-data-ingress-photo-pipeline`, from before the file was renamed), so Grafana replaces the
dashboard in place instead of creating a copy. Choose the Prometheus data source for
`DS_PROMETHEUS` when asked.
