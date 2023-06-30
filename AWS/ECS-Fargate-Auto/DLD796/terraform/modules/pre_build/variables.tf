
variable "environment" {
  type        = string
  description = "Environment"
}

variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "image_name" {
  type = string
}

variable "account_id" {
  type = string
}

variable "workspace" {
  type = string
  default = ""
}

variable "workspace_branch" {
  type = string
  default = ""
}


variable "container_build" {
  type = string
  default = "true"
}

variable "repository_name" {}
