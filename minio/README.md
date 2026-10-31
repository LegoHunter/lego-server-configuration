# MinIO

### Installation

#### Create Namespaces

```bash
kubectl create namespace minio-dev
kubectl create namespace minio-operator
```

#### Setup Cert-Manager for MinIO Operator

```bash
kubectl apply -f operator-ca-tls-secret.yaml
kubectl apply -f operator-ca-issuer.yaml
kubectl apply -f sts-tls-certificate.yaml
```

#### Install MinIO Operator with Kustomize

Get latest tag version: https://github.com/minio/operator/tags

```bash
kubectl kustomize github.com/minio/operator\?ref=<VERSION> | kubectl apply -f -
```

kubectl apply -f minio-dev-ca-certificate.yaml
kubectl apply -f minio-dev-ca-issuer.yaml
kubectl apply -f minio-dev-minio-certificate.yaml

Get latest tag version of Tenant: https://quay.io/repository/minio/minio?tab=tags&tag=latest

Edit tenant-base.yaml to set the version
RELEASE.2025-09-07T16-13-09Z

kubectl apply -f tenant-base.yaml

### Installing Minio Client

#### mc client installation script - `install-mc.sh`

```shell
#!/bin/bash
# Installs minio mc client
cd /usr/local/bin
sudo wget https://dl.min.io/client/mc/release/linux-arm64/mc
sudo chmod +x mc
./mc --help
```

#### Run mc client installation script
```
ssh sysadmin@10.0.2.51

cd ~/ansible/minio
./install-mc.sh

```

#### Setting minio-dev alias

Create minio-dev alias: `mc alias set minio-dev https://api.minio.dev.internal.legohunter.io tvattima <pwd>`
List all configured aliases: `mc alias list` 
List all buckets for alias: `mc ls minio-dev`
Create a bucket: `mc mb minio-dev/<bucket-name>`

#### Configuring Redpanda Events for a Minio Bucket

These worked:
mc admin config set minio-dev/ notify_kafka:redpanda-dev enable=on brokers="redpanda-dev-0.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-1.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-2.redpanda-dev.redpanda-dev.svc.cluster.local:9092" topic="dev-lego-bricklink-catalog-activity" sasl_username=devproducer sasl_password=<REDACTED> sasl_mechanism=SHA512 tls=on tls_skip_verify=on version="2.0.0" queue_dir="/tmp" queue_limit="100000"
mc admin config set minio-dev/ notify_kafka:redpanda-dev enable=on brokers="redpanda-dev-0.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-1.redpanda-dev.redpanda-dev.svc.cluster.local:9092,redpanda-dev-2.redpanda-dev.redpanda-dev.svc.cluster.local:9092" topic="dev-lego-photo-activity" sasl_username=devproducer sasl_password=<REDACTED> sasl_mechanism=SHA512 tls=on tls_skip_verify=off version="2.0.0" queue_dir="/tmp" queue_limit="100000"

These worked but cause some dropped events:
mc admin config set minio-dev/ notify_kafka:redpanda-dev enable=on brokers="redpanda-dev-0.dev.internal.legohunter.io:31092,redpanda-dev-1.dev.internal.legohunter.io:31092,redpanda-dev-2.dev.internal.legohunter.io:31092" topic="dev-lego-photo-activity" tls=on tls_skip_verify=off version="2.0.0" queue_dir="/tmp" queue_limit="100000"
mc admin config set minio-dev/ notify_kafka:redpanda-dev enable=on brokers="redpanda-dev-0.dev.internal.legohunter.io:31092,redpanda-dev-1.dev.internal.legohunter.io:31092,redpanda-dev-2.dev.internal.legohunter.io:31092" topic="dev-lego-photo-activity" sasl_username=devproducer sasl_password=<REDACTED> sasl_mechanism=SHA512 tls=on tls_skip_verify=off version="2.0.0" queue_dir="/tmp" queue_limit="100000"

Must run this to setup the events to publish to redpanda:
mc event add minio-dev/dev-lego-photo-upload arn:minio:sqs::redpanda-dev:kafka   --event put,delete
mc event add minio-dev/dev-lego-bricklink-catalog-upload arn:minio:sqs::redpanda-dev:kafka   --event put,delete