variable "cluster_name" {
  type        = string
  description = "The name of the EKS cluster associated with this module's resources."
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

variable "efs-csi-driver_version" {
  type        = string
  description = "The version of the EFS CSI Driver add-on to install in the cluster."
  nullable    = false
}

variable "cluster_oidc_provider_arn" {
  type        = string
  description = "The ARN of the EKS cluster's OIDC provider"
  nullable    = false
}

variable "cluster_oidc_provider" {
  type        = string
  description = "The EKS cluster's OIDC provider URL (minus the leading 'https://')"
  nullable    = false
}