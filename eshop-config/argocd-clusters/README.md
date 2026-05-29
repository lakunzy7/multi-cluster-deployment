# ArgoCD cluster registration (declarative)

ArgoCD runs on the Kind cluster (`kind-cloudopshub-local`) and deploys workloads to:

| Name | Where | Source |
|---|---|---|
| `in-cluster` | Kind itself | Auto-created by ArgoCD install |
| `gke-cloud-cluster` | GKE zonal `cloud-cluster` | This directory |

## Files

| File | Apply to | Purpose |
|---|---|---|
| `gke-argocd-sa.yaml` | **GKE** | Creates `argocd-manager` ServiceAccount + ClusterRoleBinding (cluster-admin) + long-lived token Secret in `kube-system` |
| `gke-cluster-secret.yaml` | **Kind / `argocd` ns** | ArgoCD cluster registration Secret with bearer token + CA cert + endpoint |

## Bootstrap

```bash
# 1. Create the SA on GKE
kubectl --context gke_expandox-cloudehub_europe-west1-b_cloud-cluster \
  apply -f eshop-config/argocd-clusters/gke-argocd-sa.yaml

# 2. (re-)generate the cluster Secret with current token/CA/endpoint and apply
./scripts/regen-gke-argocd-secret.sh  # see below — or just re-run the embedded one-liner

# 3. Verify
argocd cluster list
```

## Verify

```bash
argocd cluster list
# expect:
# https://34.156.236.159          gke-cloud-cluster  ...
# https://kubernetes.default.svc  in-cluster         ...
```

## If the GKE endpoint IP changes (cluster recreate)

The `server:` line in `gke-cluster-secret.yaml` is the public control-plane IP. It rarely changes during a cluster's lifetime, but after a `terraform destroy` + `terraform apply` cycle the IP **will** be different.

To regenerate the Secret:

```bash
GKE_TOKEN=$(kubectl --context gke_... -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' | base64 -d)
GKE_CA=$(kubectl --context gke_... -n kube-system get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}')
GKE_ENDPOINT=$(terraform -chdir=terraform output -raw cloud_cluster_endpoint)
# regenerate gke-cluster-secret.yaml with these values, then:
kubectl --context kind-cloudopshub-local apply -f eshop-config/argocd-clusters/gke-cluster-secret.yaml
```

Future improvement: switch to **Connect Gateway** (stable URL: `https://connectgateway.googleapis.com/v1/projects/<NUM>/locations/europe-west1/gkeMemberships/cloud-cluster`). Blocked currently by `iam.disableServiceAccountKeyCreation` org policy; would need Workload Identity Federation between Kind and GCP.

## Security note

`gke-cluster-secret.yaml` contains a long-lived bearer token + CA cert. **Do not commit the populated file to public git** — keep credentials out of source control. The file template (without the token substituted in) is safe to commit; treat the rendered version like a secret.
