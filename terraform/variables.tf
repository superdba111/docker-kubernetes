# ------------------------------------------------------------------------------
# Input variables definitions for the root module (main.tf)
# ------------------------------------------------------------------------------
variable "region" {
  type        = string
  description = "The AWS region in which to provision resources."
  nullable    = false
}

variable "account_number" {
  type        = string
  description = "The AWS account number for this VPC."
  nullable    = false
}

variable "cluster_name" {
  type        = string
  description = "The name of the EKS cluster."
  nullable    = false
}

variable "cluster_version" {
  type        = string
  description = "The Kubernetes version to use in the EKS cluster."
  nullable    = false
}

variable "project_name" {
  type        = string
  description = "The Terraform project name / repo name (used in tags for tracking)."
  nullable    = false
}

variable "nws_project_tag" {
  type        = string
  description = "The 8872_NWS_Project tag value to assign to resources."
  nullable    = false
}

variable "helm_chart_repo" {
  type        = string
  description = "Applications will be deployed to this cluster via Helm."
  nullable    = false
}

variable "vpc_id" {
  type        = string
  description = "The VPC in which to provision the EKS cluster."
  nullable    = false
}

variable "private_subnet_1a_id" {
  type        = string
  description = "The ID of the us-east-1a private subnet."
  nullable    = false
}

variable "private_subnet_1b_id" {
  type        = string
  description = "The ID of the us-east-1b private subnet."
  nullable    = false
}

variable "admin_instance_base_ami" {
  type        = string
  description = "The ID of the base image for the EKS admin instance."
  nullable    = false
}

variable "worker_node_base_ami" {
  type        = string
  description = "The ID of the base image for the EKS worker nodes."
  nullable    = false
}

variable "base_access_security_group_id" {
  type        = string
  description = "The ID of the BaseAccess security group."
  nullable    = false
}

variable "ebs_kms_key_id" {
  type        = string
  description = "The ID of the default KMS key used for EBS encryption."
  nullable    = false
}

variable "coredns_version" {
  type        = string
  description = "The version of CoreDNS to install in the cluster."
  nullable    = false
}

variable "kube-proxy_version" {
  type        = string
  description = "The version of kube-proxy to install in the cluster."
  nullable    = false
}

variable "vpc-cni_version" {
  type        = string
  description = "The version of Amazon VPC CNI to install in the cluster."
  nullable    = false
}

variable "ebs-csi-driver_version" {
  type        = string
  description = "The version of the EBS CSI Driver add-on to install in the cluster."
  nullable    = false
}

variable "mdl_prod_nat_ip_address" {
  type        = string
  description = "IP address of the NAT instance in front of Jenkins/build agents."
  nullable    = false
}

variable "efs-csi-driver_version" {
  type        = string
  description = "The version of the EFS CSI Driver add-on to install in the cluster."
  nullable    = false
}

variable "load_balancer_security_group_id" {
  type        = string
  description = "The ID of the security group that is attached to the load balancer."
  nullable    = false
}

variable "eks_cluster_worker_node_instance_type" {
  type        = string
  description = "The instance type to be used by worker nodes."
  nullable    = false
}

variable "eks_cluster_worker_nodes_desired_size" {
  type        = number
  description = "The desired size of the node group(s)."
  nullable    = false
}

variable "eks_cluster_worker_nodes_min_size" {
  type        = number
  description = "The minimum size of the node group(s)."
  nullable    = false
}

variable "eks_cluster_worker_nodes_max_size" {
  type        = number
  description = "The maximum size of the node group(s)."
  nullable    = false
}

variable "aws_lbc_helm_chart_version" {
  type        = string
  description = "The version of the AWS Load Balancer Controller Helm chart to install."
  nullable    = false
}

variable "metrics_server_helm_chart_version" {
  type        = string
  description = "The version of the Kubernetes Metrics Server Helm chart to install."
  nullable    = false
}

variable "project_contacts" {
  type        = string
  description = "A comma-separated string. Used to construct the 8872_NWS_POC tag."
  nullable    = false
}