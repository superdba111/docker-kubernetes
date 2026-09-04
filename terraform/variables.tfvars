# ------------------------------------------------------------------------------
# Variables for the mdl-sandbox AWS account.
# ------------------------------------------------------------------------------
region                                = "us-east-1"
account_number                        = "011935884485"
cluster_name                          = "datalake-1_25"
cluster_version                       = "1.29"
project_name                          = "vlab-cloud-datalake"
nws_project_tag                       = "TODO-DataLake"
project_contacts                      = "bryan.schuknecht@noaa.gov,angel.montanez@noaa.gov"
helm_chart_repo                       = "vlab-cloud-datalake-helm-charts"
vpc_id                                = "vpc-0ff2a71122243dbef"
private_subnet_1a_id                  = "subnet-0739b0384785781cc"
private_subnet_1b_id                  = "subnet-01b3659c181e7a89b"
admin_instance_base_ami               = "ami-0c7cabfbe6a3c0b01"
worker_node_base_ami                  = "ami-00dbd353fd82ed238"
base_access_security_group_id         = "sg-05ee2e7c0a27df585"
ebs_kms_key_id                        = "4955e8d4-42f3-4ec8-a062-688985c6c4f6"
mdl_prod_nat_ip_address               = "205.156.8.140/32"
load_balancer_security_group_id       = "sg-0b4b8b1f87de7ed4e"
eks_cluster_worker_node_instance_type = "m5.4xlarge"
eks_cluster_worker_nodes_desired_size = 3
eks_cluster_worker_nodes_min_size     = 3
eks_cluster_worker_nodes_max_size     = 3
# -----------------------------
# Add-ons
# -----------------------------
# CoreDNS
# Docs: https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html
# Match add-on version with Kubernetes version above.
coredns_version = "v1.11.1-eksbuild.9"
# kube-proxy
# Docs: https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html
# Match add-on version with Kubernetes version above.
kube-proxy_version = "v1.29.3-eksbuild.5"
# Amazon VPC CNI
# Docs: https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html
# Match add-on version with Kubernetes version above.
vpc-cni_version = "v1.18.2-eksbuild.1"
# Amazon EBS CSI Driver
# Docs: None (Find latest release in EKS console)
ebs-csi-driver_version = "v1.32.0-eksbuild.1"
# Amazon EFS CSI Driver
# Docs: None (Find latest release in EKS console)
efs-csi-driver_version = "v2.0.4-eksbuild.1"
# -----------------------------
# Helm Charts
# -----------------------------
metrics_server_helm_chart_version = "3.12.1"
aws_lbc_helm_chart_version        = "1.8.1"