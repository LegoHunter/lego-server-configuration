## External Secrets

```
kubectl apply -f external-secrets-namespace.yaml

helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets -n external-secrets -f external-secrets-values.yaml
```

### Setting up the external-secrets

```
kubectl create secret generic infisical-api-token -n external-secrets --from-literal=token=<YOUR_INFISICAL_API_TOKEN>
```