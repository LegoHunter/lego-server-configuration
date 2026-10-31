## Kubernetes

Use Techno Tim's Ansible scripts to setup k3s cluster:
Video: https://www.youtube.com/watch?v=CbkEWcUZ7zM
Notes: https://technotim.live/posts/k3s-etcd-ansible/

Techno Tim's Launchpad github Repository: https://github.com/timothystewart6/launchpad

### Install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

#### Helm tips

Show values for a chart: https://helm.sh/docs/helm/helm_show_values/
Can be used to generate values.yaml file for editing.

sysadmin



# Deprecated

### Install kubectl

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
--> kubectl: OK
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

#### Test kubectl installation
kubectl version --client

Copy C:\Users\tvatt\.kube\config to ~/.kube/config on linux machine 

kubectl get nodes

### Install helm
cd /usr/local/bin
sudo curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
sudo chmod 700 get_helm.sh
sudo ./get_helm.sh

#### Test helm installation
helm version


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
            - 10.0.2.51/24
         routes:
            - to: default
              via: 10.0.2.1
         nameservers:
            addresses:
               - 10.0.2.51
               - 10.0.2.52
               - 10.0.2.1
   version: 2
```



## ssh keys setup

1. On host machine, run `ssh-keygen`, do not enter passphrase.
   *_Note_*: Only need to do this 1-time on the host machine.
2. Copy public key of host machine to target machine, run `ssh-copy-id tvattima@<target-ip>`
3. Test logging-in passwordless to target machine, run `ssh tvattima@<target-ip>`

Reset a target machine's keys on host machine: 
WSL Linux: `ssh-keygen -f "/home/tvattima/.ssh/known_hosts" -R "<target-ip>"`
Windows Powershell: `type $env:USERPROFILE\.ssh\id_rsa.pub | ssh tvattima@<target-ip> "cat >> .ssh/authorized_keys"`

## Install Ansible on Ansible Host machine

https://www.cbtnuggets.com/blog/technology/devops/how-to-install-ansible-in-a-python-virtual-environment

1. sudo apt update
2. sudo apt upgrade -y
3. sudo apt-add-repository ppa:ansible/ansible
4. sudo apt update
5. sudo apt install ansible

## k3s Kubernetes Server Node installation

*_Note_*: Ensure MySQL database k3s with use k3s is configured

`sudo curl -sfL https://get.k3s.io | K3S_DATASTORE_ENDPOINT='mysql://k3s:<password>@tcp(localhost:3306)/k3s' sh -`

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