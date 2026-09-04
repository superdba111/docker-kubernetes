# -----------------------------------------------------------------------------
# Input variables for this module.
# -----------------------------------------------------------------------------
variable "account_number" {
  type        = string
  description = "The AWS account number in which to provision resources."
  nullable    = false
}

variable "vpc_id" {
  type        = string
  description = "The VPC in which to provision resources."
  nullable    = false
}

variable "cluster_name" {
  type        = string
  description = "The name of the EKS cluster associated with this module's resources."
  nullable    = false
}

variable "cluster_version" {
  type        = string
  description = "The version of Kubernetes to use in this EKS cluster."
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

variable "mdl_prod_nat_ip_address" {
  type        = string
  description = "The cluster's API server will allow public access from Jenkins."
  nullable    = false
}

variable "admin_instance_private_ip" {
  type        = string
  description = "The private IP address of the administrative EC2 instance."
  nullable    = false
}

variable "developer_instance_private_ip" {
  type        = string
  description = "The private IP address of the administrative EC2 instance."
  nullable    = false
}