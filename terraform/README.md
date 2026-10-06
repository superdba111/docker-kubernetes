
# terraform/ — EKS Cluster Provisioning

Terraform project that provisions an **Amazon EKS cluster** and supporting infrastructure on AWS: admin/developer bastion instances, cluster IAM roles, worker node groups, core add-ons, and Helm-deployed controllers (AWS Load Balancer Controller, Metrics Server).

Source: [`superdba111/docker-kubernetes/terraform`](https://github.com/superdba111/docker-kubernetes/tree/master/terraform)

## Requirements

| Tool/Provider | Version |
|---|---|
| Terraform | `~> 1.9.0` |
| `hashicorp/aws` provider | `5.56.1` |
| `hashicorp/kubernetes` provider | `2.31.0` |
| `hashicorp/helm` provider | `2.14.0` |

State is stored remotely in an **S3 backend** (block is left empty in `terraform.tf` — backend config, e.g. bucket/key/region, is supplied at `terraform init` time, in this project's case by a Jenkins pipeline via `-backend-config`).

## Directory Layout

```
terraform/
├── main.tf              # Root module — wires all child modules together
├── terraform.tf          # Backend + required_providers + required_version
├── variables.tf           # Root module input variable declarations
├── variables.tfvars        # Example/environment values (mdl-sandbox account)
└── modules/
    ├── admin_instance/              # Admin bastion EC2 instance + IAM
    ├── developer_instance/          # Developer bastion EC2 instance + IAM
    ├── eks/                         # EKS cluster, cluster IAM roles, KMS key, OIDC provider
    ├── kubernetes_config/           # Creates the "vlab" Kubernetes namespace
    ├── kubernetes_auth/             # Manages the aws-auth ConfigMap (IAM-to-RBAC mapping) + RBAC roles
    ├── eks_nodes/                   # Worker node group, launch template, LB-ingress security group
    ├── eks_addons/                  # Managed add-ons: CoreDNS, kube-proxy, VPC CNI, EBS CSI, EFS CSI
    ├── aws_load_balancer_controller/ # AWS Load Balancer Controller (IAM role + Helm release)
    └── metrics_server/              # Kubernetes Metrics Server (Helm release)
```

## What Each Module Does

- **`admin_instance`** — Creates an EC2 instance (in a private subnet) with an IAM role/policy granting full EKS admin permissions, ECR access, and Helm deployment permissions. Intended as an operator bastion for managing the cluster.
- **`developer_instance`** — Creates a second EC2 instance with a read-only IAM policy scoped to the EKS cluster, for developer access.
- **`eks`** — Creates the EKS cluster IAM service role (`AmazonEKSClusterPolicy` + `ElasticLoadBalancingFullAccess`), the node IAM role, a KMS key for cluster encryption, a security group allowing the admin instance in, the `aws_eks_cluster` resource itself, CloudWatch log group, and the cluster's OIDC provider (used later for IRSA).
- **`kubernetes_config`** — Applies baseline Kubernetes resources to the new cluster; currently creates the `vlab` namespace.
- **`kubernetes_auth`** — Manages the `aws-auth` ConfigMap, mapping the node IAM role, admin instance role, and developer instance role to Kubernetes RBAC identities/groups, plus a custom `vlab` elevated ClusterRole/Role and bindings.
- **`eks_nodes`** — Creates a security group allowing ingress from the load balancer, a launch template, and a managed multi-AZ EKS node group for worker nodes.
- **`eks_addons`** — Installs the EKS-managed add-ons: CoreDNS, kube-proxy, Amazon VPC CNI, EBS CSI driver (with its own IAM role), and EFS CSI driver (with its own IAM role).
- **`aws_load_balancer_controller`** — Creates the IAM policy/role for the AWS Load Balancer Controller (IRSA) and installs it via the `helm_release` resource.
- **`metrics_server`** — Installs the Kubernetes Metrics Server via Helm.

## Module Dependency Order (as wired in `main.tf`)

```
admin_instance ─┐
developer_instance ─┤
                    ▼
                   eks
                    │
                    ▼
            kubernetes_config
                    │
                    ▼
             kubernetes_auth
                    │
                    ▼
               eks_nodes
                    │
                    ▼
              eks_addons
                    │
            ┌───────┴────────┐
            ▼                ▼
aws_load_balancer_controller  metrics_server
```

Each stage uses `depends_on` to enforce this order (e.g., node groups can't be created before `aws-auth` is configured, or the nodes won't be able to join the cluster).

## Providers Configured

1. **`aws`** — standard AWS provider, region from `var.region`, applies two default tags (`8872_NWS_Terraform_Source`, `8872_NWS_Project`) to all resources.
2. **`kubernetes`** — authenticates to the new EKS cluster using `aws eks get-token` (exec-based auth), so no static kubeconfig is needed.
3. **`helm`** — same exec-based auth, used to install the AWS LBC and Metrics Server charts.

## Key Input Variables

See `variables.tf` for the full list with descriptions. Notable ones:

| Variable | Purpose |
|---|---|
| `region`, `account_number` | Target AWS region/account |
| `vpc_id`, `private_subnet_1a_id`, `private_subnet_1b_id` | Networking (cluster spans two AZs) |
| `cluster_name`, `cluster_version` | EKS cluster identity/version |
| `admin_instance_base_ami`, `worker_node_base_ami` | Base AMIs for bastion/worker instances |
| `base_access_security_group_id`, `load_balancer_security_group_id` | Pre-existing security groups to attach |
| `ebs_kms_key_id` | KMS key for EBS volume encryption |
| `eks_cluster_worker_node_instance_type`, `*_desired_size`, `*_min_size`, `*_max_size` | Worker node group sizing |
| `coredns_version`, `kube-proxy_version`, `vpc-cni_version`, `ebs-csi-driver_version`, `efs-csi-driver_version` | EKS add-on versions (must match the chosen `cluster_version` — see AWS's add-on compatibility docs) |
| `aws_lbc_helm_chart_version`, `metrics_server_helm_chart_version` | Helm chart versions for the two installed controllers |
| `helm_chart_repo` | Repo used for app deployments to the cluster (consumed by `admin_instance`) |
| `project_contacts` | Comma-separated contact emails, used to build a `*_POC` tag |

`variables.tfvars` contains a worked example (the `mdl-sandbox` AWS account) showing real values for every variable, including which EKS add-on version pairs with which Kubernetes version.

## Usage

```bash
# Initialize with your S3 backend config (bucket/key/region supplied separately)
terraform init -backend-config="bucket=<your-state-bucket>" \
                -backend-config="key=<your-state-key>" \
                -backend-config="region=<your-region>"

# Review the plan against your own tfvars file
terraform plan -var-file="variables.tfvars"

# Apply
terraform apply -var-file="variables.tfvars"
```

> ⚠️ `variables.tfvars` as checked into the repo targets a specific environment (account number, subnet IDs, security group IDs, KMS key, NAT IP, and internal contact emails). Replace these with your own environment's values before applying — don't apply it as-is against an account you don't intend to modify.

## Notes / Things to Verify Before Reuse

- The EKS cluster IAM role includes `ElasticLoadBalancingFullAccess` — broader than the default AWS-recommended managed policy; confirm this matches your organization's least-privilege requirements before reusing.
- The `kubernetes_auth` module grants a custom "vlab elevated" Role/ClusterRoleBinding — review and rename/remove if this project-specific RBAC grant isn't relevant to your use case.
- Add-on versions (`coredns`, `kube-proxy`, `vpc-cni`, CSI drivers) are pinned per Kubernetes minor version; update them together whenever you bump `cluster_version`.
- No `outputs.tf` at the root — only child modules expose outputs (consumed internally by other modules). Add root-level outputs if you need to surface cluster endpoint/ARNs outside Terraform.
