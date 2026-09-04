# -----------------------------------------------------------------------------
# Input variables for this module.
# -----------------------------------------------------------------------------
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

variable "admin_instance_base_ami" {
  type        = string
  description = "The AMI ID of the base image for the admin EC2 instance."
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

variable "private_subnet_id" {
  type        = string
  description = "The ID of the us-east-1a private subnet."
  nullable    = false
}

variable "base_access_security_group_id" {
  type        = string
  description = "The ID of the BaseAccess security group."
  nullable    = false
}

variable "ebs_kms_key_id" {
  type        = string
  description = "The ID of the default (AWS-managed) KMS key for EBS encryption."
  nullable    = false
}

variable "project_contacts" {
  type        = string
  description = "A comma-separated string. Used to construct the 8872_NWS_POC tag."
  nullable    = false
}