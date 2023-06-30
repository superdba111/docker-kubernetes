#Parameters
variable "vpc_id" {
  type        = string
}

variable "region" {
  type = string
}

# variable "image_version" {
#   type = string
# }

variable "image_tag" {
  type = string
}

variable "image_name" {
  type = string
}

variable "terraform_repository_name" {
  type = string
}

variable "terraform_environment_name" {
  type = string
}

variable "terraform_workspace_name" {
  type = string
}


variable "terraform_workspace_branch" {
  type = string
}

variable "subnet_ids" {
}

variable "task_role_arn" {
  type = string
}

variable "cpu" {
  type = string
}

variable "memory" {
  type = string
}

variable "schedule" {
  type = string
}

variable "datadog_secret"{}