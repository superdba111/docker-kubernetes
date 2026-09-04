# -----------------------------------------------------------------------------
# Project root module.
# -----------------------------------------------------------------------------
# Initialize the AWS provider.
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "8872_NWS_Terraform_Source" = var.project_name
      "8872_NWS_Project"          = var.nws_project_tag
    }
  }
}

# This module is used to create an administrative EC2 instance and related resources.
module "admin_instance" {
  source                        = "./modules/admin_instance"
  region                        = var.region
  account_number                = var.account_number
  nws_project_tag               = var.nws_project_tag
  admin_instance_base_ami       = var.admin_instance_base_ami
  cluster_name                  = var.cluster_name
  private_subnet_id             = var.private_subnet_1a_id
  base_access_security_group_id = var.base_access_security_group_id
  ebs_kms_key_id                = var.ebs_kms_key_id
  helm_chart_repo               = var.helm_chart_repo
  project_contacts              = var.project_contacts
}

# This module is used to create a developer EC2 instance and related resources.
module "developer_instance" {
  source                        = "./modules/developer_instance"
  region                        = var.region
  account_number                = var.account_number
  nws_project_tag               = var.nws_project_tag
  admin_instance_base_ami       = var.admin_instance_base_ami
  cluster_name                  = var.cluster_name
  private_subnet_id             = var.private_subnet_1a_id
  base_access_security_group_id = var.base_access_security_group_id
  ebs_kms_key_id                = var.ebs_kms_key_id
  project_contacts              = var.project_contacts
}

# This module is used to create the EKS cluster and related resources.
module "eks" {
  source                        = "./modules/eks"
  account_number                = var.account_number
  vpc_id                        = var.vpc_id
  cluster_name                  = var.cluster_name
  cluster_version               = var.cluster_version
  private_subnet_1a_id          = var.private_subnet_1a_id
  private_subnet_1b_id          = var.private_subnet_1b_id
  mdl_prod_nat_ip_address       = var.mdl_prod_nat_ip_address
  admin_instance_private_ip     = module.admin_instance.private_ip
  developer_instance_private_ip = module.developer_instance.private_ip
}

# Initialize the Kubernetes Terraform provider
provider "kubernetes" {
  host                   = module.eks.cluster_api_server_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
}

# This module is used to apply Kubernetes configurations to the cluster.
module "kubernetes_config" {
  source     = "./modules/kubernetes_config"
  depends_on = [module.eks]
}

# This module is used to create/manage the aws-auth ConfigMap.
module "kubernetes_auth" {
  source                      = "./modules/kubernetes_auth"
  depends_on                  = [module.kubernetes_config]
  cluster_node_role_arn       = module.eks.cluster_node_role_arn
  admin_instance_role_arn     = module.admin_instance.admin_instance_role_arn
  developer_instance_role_arn = module.developer_instance.developer_instance_role_arn
  account_number              = var.account_number
}

# This module is used to create/manage node groups within the EKS cluster.
module "eks_nodes" {
  source                                = "./modules/eks_nodes"
  depends_on                            = [module.kubernetes_auth]
  vpc_id                                = var.vpc_id
  cluster_name                          = var.cluster_name
  region                                = var.region
  account_number                        = var.account_number
  nws_project_tag                       = var.nws_project_tag
  private_subnet_1a_id                  = var.private_subnet_1a_id
  private_subnet_1b_id                  = var.private_subnet_1b_id
  ebs_kms_key_id                        = var.ebs_kms_key_id
  worker_node_base_ami                  = var.worker_node_base_ami
  base_access_security_group_id         = var.base_access_security_group_id
  cluster_node_role_arn                 = module.eks.cluster_node_role_arn
  cluster_security_group_id             = module.eks.cluster_security_group_id
  cluster_endpoint                      = module.eks.cluster_api_server_endpoint
  cluster_certificate_authority_data    = module.eks.cluster_certificate_authority_data
  load_balancer_security_group_id       = var.load_balancer_security_group_id
  eks_cluster_worker_node_instance_type = var.eks_cluster_worker_node_instance_type
  eks_cluster_worker_nodes_desired_size = var.eks_cluster_worker_nodes_desired_size
  eks_cluster_worker_nodes_min_size     = var.eks_cluster_worker_nodes_min_size
  eks_cluster_worker_nodes_max_size     = var.eks_cluster_worker_nodes_max_size
  project_contacts                      = var.project_contacts
}

# This module is used to install/manage EKS cluster add-ons.
module "eks_addons" {
  source                    = "./modules/eks_addons"
  depends_on                = [module.eks_nodes]
  cluster_name              = var.cluster_name
  coredns_version           = var.coredns_version
  kube-proxy_version        = var.kube-proxy_version
  vpc-cni_version           = var.vpc-cni_version
  ebs-csi-driver_version    = var.ebs-csi-driver_version
  efs-csi-driver_version    = var.efs-csi-driver_version
  cluster_oidc_provider_arn = module.eks.cluster_oidc_provider_arn
  cluster_oidc_provider     = module.eks.cluster_oidc_provider
}

# Initialize the Helm provider.
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_api_server_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
      command     = "aws"
    }
  }
}

# This module installs the AWS LBC and associated resources.
module "aws_load_balancer_controller" {
  source                     = "./modules/aws_load_balancer_controller"
  depends_on                 = [module.eks_addons]
  cluster_name               = var.cluster_name
  region                     = var.region
  vpc_id                     = var.vpc_id
  cluster_oidc_provider_arn  = module.eks.cluster_oidc_provider_arn
  cluster_oidc_provider      = module.eks.cluster_oidc_provider
  aws_lbc_helm_chart_version = var.aws_lbc_helm_chart_version
}

# This module installs the Kubernetes Metrics Server.
module "metrics_server" {
  source                            = "./modules/metrics_server"
  depends_on                        = [module.eks_addons]
  metrics_server_helm_chart_version = var.metrics_server_helm_chart_version
}