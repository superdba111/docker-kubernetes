variable "region" {
  type    = string
  default = "us-gov-west-1"
}

variable "environment" {
  type    = string
  default = "govhigh"
}

variable "eks_cluster_name" {
  type    = string
  default = "foundry-govhigh"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}
