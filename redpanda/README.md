# Redpanda

### Installing rpk

ssh into 10.0.2.52
`curl -1sLf 'https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.deb.sh' | sudo -E bash`
`sudo apt install redpanda`

#### Run iotune to create `/etc/redpanda/io-config.yaml`

`sudo rpk iotune`

`sudo cat /etc/redpanda/io-config.yaml`
--> should show output of file

### Installing Redpanda using Redpanda Operator

#### Create redpanda configmap
`kubectl create namespace redpanda-dev`
`cd ~/ansible/redpanda`
`scp sysadmin@10.0.2.52:/etc/redpanda/io-config.yaml .`
`kubectl create configmap redpanda-io-config --namespace redpanda-dev --from-file=./io-config.yaml`

#### Create legohunter.io ssl certificate using cert-manager

`kubectl apply -f redpanda-dev-internal-legohunter-io-production-certificate.yaml`

#### Install redpanda cluster in Kubernetes

`kubectl auth can-i create CustomResourceDefinition --all-namespaces`
--> should be 'yes'

`helm repo add redpanda https://charts.redpanda.com`

`helm repo update`

`helm upgrade --install redpanda-controller redpanda/operator --namespace redpanda-dev --create-namespace --version v25.1.3 --set crds.enabled=true`

#### Deploy the cluster 


`kubectl --namespace redpanda-dev create secret generic redpanda-superusers --from-file=superusers.txt`

### Update PiHole DNS with redpanda pod cluster IPs

`kubectl get pods -n redpanda-dev -o wide`

Update pihole internal DNS with correct IPs for:
repanda-0
repanda-1
repanda-2

### Disable enterprise features in Redpanda

Show enterprise features enabled: `kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk cluster license info`
Disable Enterprise Features:
`kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk cluster config set core_balancing_continuous false`
`kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk cluster config set partition_autobalancing_mode off`

If console shows Enterprise Features enabled, Inspect the overlay on the console UI in the browser and remove the DIV. This worked on 2/10/26.

#### Create devproducer

`kubectl apply -f devproducer-password-secret.yaml`
`kubectl exec -it redpanda-0 -n redpanda-dev -- rpk security user create devproducer -p <your-strong-password> --mechanism SCRAM-SHA-512`
`kubectl apply -f devproducer-acl.yaml`

#### Create topic in dev console

kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk security user create devproducer -p <your-strong-password> --mechanism SCRAM-SHA-512
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk security user create devconsumer -p <your-strong-password> --mechanism SCRAM-SHA-512

kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic create dev-test-topic -p 3 -r 3
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devproducer --operation write,describe --topic dev-test-topic

kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic create dev-lego-photo-activity -p 3 -r 3
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devproducer --operation write,describe --topic dev-lego-photo-activity
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --topic dev-lego-photo-activity
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --group lego-photo-activity-group

----------------------------------------------------------------------------

-- Bricklink
mc rb minio-dev/dev-bricklink-catalog-upload --force
mc mb minio-dev/dev-bricklink-catalog-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic delete dev-bricklink-catalog-upload 
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic create dev-bricklink-catalog-upload -p 3 -r 3
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devproducer --operation write,describe --topic dev-bricklink-catalog-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --topic dev-bricklink-catalog-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --group dev-bricklink-catalog-upload-group
mc admin config set minio-dev/ notify_kafka:dev-bricklink-catalog-upload enable=on \
  brokers="redpanda-dev-0.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-1.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-2.redpanda-dev.redpanda-dev.svc.cluster.local:9092" \
  topic="dev-bricklink-catalog-upload" sasl_username=devproducer sasl_password=<REDACTED> sasl=on sasl_mechanism=SHA512 tls=on tls_skip_verify=on version="2.0.0" queue_dir="/tmp" queue_limit="100000"
mc event add minio-dev/dev-bricklink-catalog-upload arn:minio:sqs::dev-bricklink-catalog-upload:kafka   --event put,delete
mc admin service restart minio-dev/

kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic delete dev-bricklink-catalog-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic create dev-bricklink-catalog-entry -p 3 -r 3
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devproducer --operation write,describe --topic dev-bricklink-catalog-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --topic dev-bricklink-catalog-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --group dev-bricklink-catalog-entry-group

mc rb minio-dev/dev-bricklink-category-upload --force
mc mb minio-dev/dev-bricklink-category-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic delete dev-bricklink-category-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic create dev-bricklink-category-upload -p 3 -r 3
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devproducer --operation write,describe --topic dev-bricklink-category-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --topic dev-bricklink-category-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --group dev-bricklink-category-upload-group
mc admin config set minio-dev/ notify_kafka:dev-bricklink-category-upload enable=on \
  brokers="redpanda-dev-0.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-1.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-2.redpanda-dev.redpanda-dev.svc.cluster.local:9092" \
  topic="dev-bricklink-category-upload" sasl_username=devproducer sasl_password=<REDACTED> sasl=on sasl_mechanism=SHA512 tls=on tls_skip_verify=on version="2.0.0" queue_dir="/tmp" queue_limit="100000"
mc admin service restart minio-dev/
mc event add minio-dev/dev-bricklink-category-upload arn:minio:sqs::dev-bricklink-category-upload:kafka   --event put,delete

kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic delete dev-bricklink-category-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic create dev-bricklink-category-entry -p 3 -r 3
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devproducer --operation write,describe --topic dev-bricklink-category-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --topic dev-bricklink-category-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --group dev-bricklink-category-entry-group

-- Rebrickable
mc rb minio-dev/dev-rebrickable-catalog-upload --force
mc mb minio-dev/dev-rebrickable-catalog-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic delete dev-rebrickable-catalog-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic create dev-rebrickable-catalog-upload -p 3 -r 3
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devproducer --operation write,describe --topic dev-rebrickable-catalog-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --topic dev-rebrickable-catalog-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --group dev-rebrickable-catalog-upload-group
mc admin config set minio-dev/ notify_kafka:dev-rebrickable-catalog-upload enable=on \
  brokers="redpanda-dev-0.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-1.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-2.redpanda-dev.redpanda-dev.svc.cluster.local:9092" \
  topic="dev-rebrickable-catalog-upload" sasl_username=devproducer sasl_password=<REDACTED> sasl=on sasl_mechanism=SHA512 tls=on tls_skip_verify=on version="2.0.0" queue_dir="/tmp" queue_limit="100000"
mc admin service restart minio-dev/
mc event add minio-dev/dev-rebrickable-catalog-upload arn:minio:sqs::dev-rebrickable-catalog-upload:kafka   --event put,delete

kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic delete dev-rebrickable-catalog-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic create dev-rebrickable-catalog-entry -p 3 -r 3
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devproducer --operation write,describe --topic dev-rebrickable-catalog-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --topic dev-rebrickable-catalog-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --group dev-rebrickable-catalog-entry-group

mc rb minio-dev/dev-rebrickable-category-upload --force
mc mb minio-dev/dev-rebrickable-category-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic delete dev-rebrickable-category-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic create dev-rebrickable-category-upload -p 3 -r 3
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devproducer --operation write,describe --topic dev-rebrickable-category-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --topic dev-rebrickable-category-upload
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --group dev-rebrickable-category-upload-group
mc admin config set minio-dev/ notify_kafka:dev-rebrickable-category-upload enable=on \
brokers="redpanda-dev-0.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-1.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-2.redpanda-dev.redpanda-dev.svc.cluster.local:9092" \
topic="dev-rebrickable-category-upload" sasl_username=devproducer sasl_password=<REDACTED> sasl=on sasl_mechanism=SHA512 tls=on tls_skip_verify=on version="2.0.0" queue_dir="/tmp" queue_limit="100000"
mc admin service restart minio-dev/
mc event add minio-dev/dev-rebrickable-category-upload arn:minio:sqs::dev-rebrickable-category-upload:kafka   --event put,delete

kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic delete dev-rebrickable-category-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk topic create dev-rebrickable-category-entry -p 3 -r 3
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devproducer --operation write,describe --topic dev-rebrickable-category-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --topic dev-rebrickable-category-entry
kubectl exec -it redpanda-dev-0 -n redpanda-dev -- rpk acl create --allow-principal devconsumer --operation read,describe --group dev-rebrickable-category-entry-group



Test by running


### Verify that each Redpanda broker is scheduled on only one Kubernetes node:

`kubectl get pod --namespace redpanda-dev -o=custom-columns=NODE:.spec.nodeName,NAME:.metadata.name -l app.kubernetes.io/component=redpanda-statefulset`
`kubectl get pod --namespace redpanda-test -o=custom-columns=NODE:.spec.nodeName,NAME:.metadata.name -l app.kubernetes.io/component=redpanda-statefulset`
`kubectl get pod --namespace redpanda-prod -o=custom-columns=NODE:.spec.nodeName,NAME:.metadata.name -l app.kubernetes.io/component=redpanda-statefulset`

# DEPRECATED

Save below yaml as `redpanda-cluster-dev.yaml`
```yaml
apiVersion: v1
items:
  - apiVersion: cluster.redpanda.com/v1alpha2
    kind: Redpanda
    metadata:
      annotations:
        cluster.redpanda.com/managed: "true"
        kubectl.kubernetes.io/last-applied-configuration: |
          {"apiVersion":"cluster.redpanda.com/v1alpha2","kind":"Redpanda","metadata":{"annotations":{"cluster.redpanda.com/managed":"true","operator.redpanda.com/config-sync-mode":"additive","operator.redpanda.com/restart-cluster-on-config-change":"false"},"creationTimestamp":"2025-08-22T22:02:11Z","finalizers":["operator.redpanda.com/finalizer"],"generation":3,"name":"redpanda-dev","namespace":"redpanda-dev","resourceVersion":"10360706","uid":"05ae0036-94ec-40a8-9572-74540677aa5e"},"spec":{"chartRef":{},"clusterSpec":{"auth":{"sasl":{"enabled":true,"secretRef":"redpanda-superusers","users":[]}},"commonLabels":{"env":"dev"},"external":{"domain":"dev.internal.legohunter.io","enabled":true,"type":"NodePort"},"fullnameOverride":"redpanda","image":{"tag":"v25.2.1"},"listeners":{"admin":{"external":{"default":{"advertisedPorts":[31644],"enabled":true}},"tls":{"enabled":true,"requireClientAuth":false}},"http":{"external":{"default":{"advertisedPorts":[30082],"enabled":true}}},"kafka":{"external":{"default":{"advertisedPorts":[31092],"enabled":true}},"tls":{"enabled":true,"requireClientAuth":false}},"rpc":{"port":33146},"schemaRegistry":{"external":{"default":{"advertisedPorts":[30081],"enabled":true}},"tls":{"enabled":true,"requireClientAuth":false}}},"statefulset":{"additionalRedpandaCmdFlags":["--io-properties-file=/etc/redpanda-io-config/io-config.yaml"],"extraVolumeMounts":"- name: redpanda-io-config\n  mountPath: /etc/redpanda-io-config","extraVolumes":"- name: redpanda-io-config\n  configMap:\n    name: redpanda-io-config","sideCars":{"args":["--no-set-superusers"]}},"tls":{"certs":{"external":{"caEnabled":false,"issuerRef":{"kind":"ClusterIssuer","name":"letsencrypt-production"}}},"enabled":true}}}}
        operator.redpanda.com/config-sync-mode: additive
        operator.redpanda.com/restart-cluster-on-config-change: "false"
      creationTimestamp: "2025-09-23T12:22:44Z"
      finalizers:
        - operator.redpanda.com/finalizer
      generation: 1
      name: redpanda-dev
      namespace: redpanda-dev
      resourceVersion: "1330519"
      uid: ce38e14e-d18d-4dce-a2e5-5d13a21caf38
    spec:
      chartRef: {}
      clusterSpec:
        auth:
          sasl:
            enabled: true
            secretRef: redpanda-superusers
            users: []
        commonLabels:
          env: dev
        external:
          domain: dev.internal.legohunter.io
          enabled: true
          type: NodePort
        fullnameOverride: redpanda
        image:
          tag: v25.2.1
        listeners:
          admin:
            external:
              default:
                advertisedPorts:
                  - 31644
                enabled: true
            tls:
              enabled: true
              requireClientAuth: false
          http:
            external:
              default:
                advertisedPorts:
                  - 30082
                enabled: true
          kafka:
            external:
              default:
                advertisedPorts:
                  - 31092
                enabled: true
            tls:
              enabled: true
              requireClientAuth: false
          rpc:
            port: 33146
          schemaRegistry:
            external:
              default:
                advertisedPorts:
                  - 30081
                enabled: true
            tls:
              enabled: true
              requireClientAuth: false
        statefulset:
          additionalRedpandaCmdFlags:
            - --io-properties-file=/etc/redpanda-io-config/io-config.yaml
          extraVolumeMounts: |-
            - name: redpanda-io-config
              mountPath: /etc/redpanda-io-config
          extraVolumes: |-
            - name: redpanda-io-config
              configMap:
                name: redpanda-io-config
          sideCars:
            args:
              - --no-set-superusers
        tls:
          certs:
            external:
              caEnabled: false
              issuerRef:
                kind: ClusterIssuer
                name: letsencrypt-production
          enabled: true
```

`kubectl apply -f redpanda-cluster-dev.yaml --namespace redpanda-dev`
