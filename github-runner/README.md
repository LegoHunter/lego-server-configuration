# Github Action Runners

### Installing

https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/authenticate-to-the-api#deploying-using-personal-access-token-classic-authentication

Create private key in Github Application in the LegoHunter Organization
Download pem file

Setup PAT for Organization Runner scopes: admin:org
https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic

#### Create github auth secret
kubectl create secret generic arc-runners-auth \
--namespace=arc-runners \
--from-literal=github_app_id=2225355 \
--from-literal=github_app_installation_id=92798093 \
--from-file=github_app_private_key=legohunter-arc.2026-01-28.private-key.pem

#### Install action runner controller
helm upgrade --install arc-controller \
oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
-f gha-runner-scale-set-controller-values.yaml \
--namespace arc-runners

#### Install action runner scaleset
helm upgrade --install arc-runner \
oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
-f gha-runner-scale-set-values.yaml \
--namespace arc-runners \
--set githubConfigUrl=https://github.com/LegoHunter \
--set githubConfigSecret.github_token="<REDACTED>"

#### Create kubeconfig secret for github Runner Docker image 
kubectl create secret generic arc-runner-kubeconfig \
--namespace arc-runners \
--from-file=kubeconfig=/home/sysadmin/.kube/config

#### Build Docker Image for ARC runner image that runs on homelab kubernetes cluster
edit Dockerfile and update this line to latest runner version:
```
FROM ghcr.io/actions/actions-runner:X.YYY.Z
```


#### Build Docker Image for ARC runner image that runs on homelab kubernetes cluster
sudo docker build --no-cache -t quay.io/tvattima/arc-runner-arm64:k8s-v<X> .

#### Publish Docker Image to quay
sudo docker push quay.io/tvattima/arc-runner-arm64:k8s-v<X>

####
sudo nano gha-runner-scale-set-values.yaml

Edit this line:
```yaml
image: quay.io/tvattima/arc-runner-arm64:k8s-v<X>
```

Then run helm upgrade:
```bash
helm upgrade --install arc-runner \
oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
-f gha-runner-scale-set-values.yaml \
--namespace arc-runners \
--set githubConfigUrl=https://github.com/LegoHunter \
--set githubConfigSecret.github_token="<REDACTED>"
```



### References
https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/quickstart

https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic
Setup PAT for Organization Runner scopes: admin:org

https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/authenticate-to-the-api#deploying-using-personal-access-token-classic-authentication

### Cleanup
helm uninstall arc-controller -n arc-runners
helm uninstall arc-runner -n arc-runners
kubectl delete secret  arc-runners-auth -n arc-runners
kubectl delete secret arc-runner-kubeconfig -n arc-runners


