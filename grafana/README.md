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

