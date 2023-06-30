
terraform {
  required_version = "~> 1.3"

  required_providers {
    aws = {
      source               = "hashicorp/aws"
      configuration_aliases = [aws.environment]
    }

    datadog = {
      source = "DataDog/datadog"
    }
  }

  backend "s3" {
    bucket         = "terraform.shared-services.e.inc"
    key            = "reporting/us-east-1/development/development.tfstate"
    region         = "us-east-1"
    role_arn       = "arn:aws:iam::711182801733:role/Terraform"
    encrypt        = true
  }
} 

locals {
  terraform_shared_iam_role = "arn:aws:iam::711182801733:role/Terraform"

  workspace_branch = var.terraform_workspace_name == "" ? "" : "${var.terraform_workspace_branch}"
  repository_name = format("%s/%s", var.image_name,local.workspace_branch) 
} 

//Import Data
data "aws_caller_identity" "reporting" {
  provider = aws.environment
}

data "aws_vpc" "this" {
  provider = aws.environment

  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "subnets" {
  provider = aws.environment
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags   = {
    NamePrefix = format("%s-standard", data.aws_vpc.this.tags["Name"])
  }
}

module "datadog_secret" {
  source    = "git@github.com:carmigo/infrastructure///modules/security/get_secret"
  providers = {
    aws = aws.environment
  }

  arn = var.datadog_secret_arn
}

// Do not use this provider. Exists only to prevent Terraform to ask for default region
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "shared-services"
  region = var.terraform_environment_region

  assume_role {
    role_arn = "arn:aws:iam::711182801733:role/Terraform"
  }
}

provider "aws" {
  alias  = "environment"
  region = var.terraform_environment_region

  assume_role {
    role_arn = var.terraform_environment_iam_role
  }
}

provider "datadog" {
  api_key = module.datadog_secret.secret_value["api_key"]
  app_key = module.datadog_secret.secret_value["app_key"]
}

// Environment variables

variable "terraform_environment_name" {
  type = string
}

variable "terraform_environment_iam_role" {
  type = string
}

variable "terraform_environment_region" {
  type = string
}
// Repository variables

variable "terraform_repository_name" {
  type = string
}
  
variable "terraform_workspace_name" {
  type = string
}

variable "terraform_workspace_branch" {
  type = string
}

variable "terraform_repository_commit_hash" {
  type = string
}
variable "vpc_name" {
  type = string
}

// Container registry

variable "terraform_container_registry" {
  type = string
}

variable "terraform_state_path" {
  type = string
  default = ""
}

variable "container_version" {
  type = string
  default = "cd terr  "
}

#Parameters

variable "datadog_secret_arn" {
  type = string
}

variable "service_type" {
  type = string
}

variable "image_name" {
  type = string
}

variable "account_id" {
  type = string
}

variable "cpu" {
  type = string
  default = "1024"
}

variable "memory" {
  type = string
  default = "2048"
}

variable "schedule" {
  type = string
}

variable "ecr_base" {}
variable "new_base" {
  type = string
  default = "false"
  } 

variable "container_build" {
  type = string
  default = "true"
}

variable "processed_s3_bucket" {}
variable "landing_s3_bucket" {}
variable "published_s3_bucket" {}  