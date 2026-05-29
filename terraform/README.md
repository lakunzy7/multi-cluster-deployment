# Terraform — CloudOpsHub GCP infrastructure (lab / free-tier)

Provisions a minimal, low-cost GCP footprint for the cloud half of the multi-cluster deployment.

## What it creates (13 resources)

- **VPC** + 2 subnets + 2 firewall rules
- **GKE zonal cluster** in `europe-west1-b` (qualifies for the monthly free-tier control-plane credit)
- **Custom Spot node pool**: 2 × `e2-medium`, 50 GB pd-standard
- **3 × GCS buckets**: backups + 2 cluster log buckets
- **3 × API enablements**: compute, container, storage

**Not** included (deliberately):
- ❌ Cloud SQL (PostgreSQL runs in-cluster as a StatefulSet)
- ❌ Secret Manager (k8s Secrets instead)
- ❌ Private VPC peering / global addresses (not needed without Cloud SQL)
- ❌ Cluster autoscaling (fixed 2-node Spot pool)

## File layout

| File | Purpose |
|---|---|
| `backend.tf` | `terraform {}` block + local state backend |
| `providers.tf` | Provider versions (google, kubernetes, helm) + provider config + shared data sources |
| `variables.tf` | Input variables (project, region, **zone**, cluster name, node size) |
| `main.tf` | VPC, subnets, firewall, GKE zonal cluster + Spot node pool, GCS buckets, API enablement |
| `local-cluster.tf` | GCS log buckets for both local + cloud clusters |
| `outputs.tf` | Outputs: cluster endpoint, CA cert, zone-based kubeconfig command, bucket names |
| `terraform.tfvars` | Real values |
| `terraform.tfvars.example` | Template for new operators |

## Prerequisites

- `terraform` >= 1.0
- `gcloud` authenticated and pointed at the target project
- Application Default Credentials with quota project set:
  ```bash
  gcloud auth application-default login
  gcloud auth application-default set-quota-project <PROJECT_ID>
  ```
- Required APIs enabled (Terraform also enables them):
  ```bash
  gcloud services enable compute.googleapis.com container.googleapis.com \
    storage.googleapis.com
  ```

## Usage

```bash
# from repo root
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=tfplan
terraform -chdir=terraform apply tfplan
```

After apply, fetch the GKE kubeconfig (note: `--zone`, not `--region`):

```bash
gcloud container clusters get-credentials cloud-cluster \
  --zone europe-west1-b --project <PROJECT_ID>
```

## Destruction (tear down everything)

```bash
terraform -chdir=terraform destroy
```

This removes all 13 resources: GKE cluster, VPC, firewall, GCS buckets. The GCP project itself is not touched.

> **Warning:** `destroy` is irreversible. GCS bucket contents are deleted permanently. Copy anything you want to keep first.

To remove a single resource instead of everything:

```bash
terraform -chdir=terraform destroy -target=google_container_node_pool.cloud_pool
```

To stop paying for nodes without destroying the cluster, scale to 0:

```bash
gcloud container clusters resize cloud-cluster --zone europe-west1-b --num-nodes 0
```

## Cost estimate (europe-west1, on-demand, 2026)

| Component | Spec | Monthly |
|---|---|---:|
| GKE zonal control plane | Free-tier credit applies | **$0** |
| Node pool | 2 × e2-medium **Spot** | ~$22 |
| PD-standard disks | 2 × 50 GB | ~$4 |
| GCS buckets | Standard, ~empty | ~$0.20 |
| Egress | ~10 GB/mo | ~$1.20 |
| **Total** | | **~$27/mo** |

Compared to the original regional+on-demand+CloudSQL design (~$160/mo), this saves ~$133/mo (83%).

## Spot caveats

Spot nodes can be preempted at any time with ~30s notice. For a lab this is fine.

For services that must survive preemption (e.g. ArgoCD, Postgres StatefulSet), use:
- `PodDisruptionBudget`s
- Multiple replicas where possible
- `tolerations:` on the `cloud.google.com/gke-spot=true:NoSchedule` taint Spot pools carry by default
