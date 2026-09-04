variable "vpc_id" {
  type        = string
  description = "The VPC in which to provision resources."
  nullable    = false
}

variable "region" {
  type        = string
  description = "The AWS region in which to provision resources."
  nullable    = false
}

variable "account_number" {
  type        = string
  description = "The AWS account number in which to provision resources."
  nullable    = false
}

variable "cluster_name" {
  type        = string
  description = "The name of the EKS cluster associated with this module's resources."
  nullable    = false
}

variable "nws_project_tag" {
  type        = string
  description = "The 8872_NWS_Project tag value to assign to resources."
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

variable "ebs_kms_key_id" {
  type        = string
  description = "The ID of the default KMS key used for EBS encryption."
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

variable "cluster_node_role_arn" {
  type        = string
  description = "The ARN of the IAM role used by cluster nodes."
  nullable    = false
}

variable "cluster_security_group_id" {
  type        = string
  description = "The EKS cluster security group. Used for control plane-to-data plane communication."
  nullable    = false
}

variable "cluster_endpoint" {
  type        = string
  description = "The cluster's Kubernetes API server endpoint."
  nullable    = false
}

variable "cluster_certificate_authority_data" {
  type        = string
  description = "The cluster's base64-encoded certificate data."
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

variable "project_contacts" {
  type        = string
  description = "A comma-separated string. Used to construct the 8872_NWS_POC tag."
  nullable    = false
}