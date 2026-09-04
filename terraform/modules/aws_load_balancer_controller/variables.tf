# -----------------------------------------------------------------------------
# Input variables for this module.
# -----------------------------------------------------------------------------
variable "cluster_name" {
  type        = string
  description = "The name of the EKS cluster associated with this module's resources."
  nullable    = false
}

variable "region" {
  type        = string
  description = "The AWS region in which to provision resources."
  nullable    = false
}

variable "vpc_id" {
  type        = string
  description = "The VPC in which to provision the EKS cluster."
  nullable    = false
}

variable "cluster_oidc_provider_arn" {
  type        = string
  description = "The ARN of the EKS cluster's OIDC provider."
  nullable    = false
}

variable "cluster_oidc_provider" {
  type        = string
  description = "The EKS cluster's OIDC provider (URL minus the leading https://)."
  nullable    = false
}

variable "aws_lbc_helm_chart_version" {
  type        = string
  description = "The version of the AWS Load Balancer Controller Helm chart to install."
  nullable    = false
}