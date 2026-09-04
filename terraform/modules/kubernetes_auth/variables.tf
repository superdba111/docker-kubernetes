# -----------------------------------------------------------------------------
# Input variables for this module.
# -----------------------------------------------------------------------------
variable "cluster_node_role_arn" {
  type        = string
  description = "The ARN of the IAM role that's assigned to the cluster's nodes."
  nullable    = false
}

variable "admin_instance_role_arn" {
  type        = string
  description = "The ARN of the IAM role that's assigned to the admin EC2 instance."
  nullable    = false
}

variable "developer_instance_role_arn" {
  type        = string
  description = "The ARN of the IAM role that's assigned to the developer EC2 instance."
  nullable    = false
}

variable "account_number" {
  type        = string
  description = "The AWS account number for this VPC."
  nullable    = false
}