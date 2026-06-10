## OTEL

### Helm
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

```shell
helm install otel-collector open-telemetry/opentelemetry-collector \
-n observability \
--set image.repository="otel/opentelemetry-collector-k8s" \
--set image.tag="0.79.0" \
--set mode=deployment \
-f values-otel.yaml
```

helm install otel-collector open-telemetry/opentelemetry-collector -n observability --set image.repository="otel/opentelemetry-collector-k8s" --set mode=deployment -f values-otel.yaml




### otel-collector-config.yaml




```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          http:
          grpc:

    processors:
      batch:

    exporters:
      logging:
        loglevel: debug

    service:
      pipelines:
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [logging]

        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [logging]
```

### otel-collector-deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-collector
spec:
  replicas: 1
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
        - name: otel-collector
          image: otel/opentelemetry-collector:latest
          args: ["--config=/etc/otel/config.yaml"]
          ports:
            - containerPort: 4317 # gRPC
            - containerPort: 4318 # HTTP
          volumeMounts:
            - name: config-volume
              mountPath: /etc/otel
      volumes:
        - name: config-volume
          configMap:
            name: otel-collector-config
```

### otel-collector-service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: otel-collector
spec:
  selector:
    app: otel-collector
  ports:
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
    - name: otlp-http
      port: 4318
      targetPort: 4318
```