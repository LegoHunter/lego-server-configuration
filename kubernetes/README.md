# Server setup

hostname: `legolandserver1`

ip: 10.0.0.9

## Networking

edit file: `sudo nano /etc/netplan/50-cloud-init.yaml` 

```yaml
network:
    ethernets:
        eth0:
            dhcp4: no
            addresses:
               - 10.0.0.9/24
            routes:
               - to: default
                 via: 10.0.0.1
            nameservers:
               addresses: [10.0.0.1]
    version: 2
```

## k3s Kubernetes Server Node installation

*_Note_*: Ensure MySQL database k3s with use k3s is configured

`sudo curl -sfL https://get.k3s.io | K3S_DATASTORE_ENDPOINT='mysql://k3s:N1njago!@tcp(localhost:3306)/k3s' sh -`

## k3s Worker Node installation

1. Get Server token:
   ```shell
   sudo cat /var/lib/rancher/k3s/server/node-token
   ```
1. Take token output and put in next command:
   ```shell
   sudo curl -sfL https://get.k3s.io | K3S_URL=https://10.0.0.9:6443 K3S_TOKEN=<token-from-above> sh -
   ```

### Lens dashboard

On windows machine, run `lens`

### Configuration files

On legolandserver1 (10.0.0.9)

```shell
cd /etc
sudo mkdir .credentials
sudo chown tvattima .credentials
```

On Windows machine, run:

```shell
 scp -r C:\Users\tvatt\.credentials\ tvattima@10.0.0.9:/etc
```

### Create secret from file on legolandserver (10.0.0.9)

`sudo kubectl create secret generic bricklink-client-api-keys --from-file=/etc/.credentials/bricklink/bricklink-client-api-keys.json --namespace sandbox`

Kubernetes Dashboard
========================================

**_Currently non-functioning_**

sudo kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc5/aio/deploy/recommended.yaml

kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard-kong-proxy 8001:8001 --address 0.0.0.0

https://10.0.0.10:18443/#/login

sudo kubectl create token admin-user -n kubernetes-dashboard

kubectl -n kubernetes-dashboard get svc

### Copy .credentials to legolandserver1

`scp -r d:\dev\config\.credentials\* tvattima@legolandserver1:/etc/.credentials`

`sudo kubectl create secret generic database-configuration --from-file=/etc/.credentials/database/database-configuration.yml --namespace sandbox`