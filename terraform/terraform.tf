# -----------------------------------------------------------------------------
# Terraform project configuration
# -----------------------------------------------------------------------------
terraform {
  # Store state remotely in AWS S3.
  # Jenkins pipelines are responsible for additional backend configuration.
  backend "s3" {
  }
  # Specify providers that will be used by this project.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.56.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.31.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.14.0"
    }
  }
  # Specify required version of Terraform for this project.
  required_version = "~> 1.9.0"
}