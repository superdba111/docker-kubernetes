terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "s3" {
    bucket            = "foundry-govhigh-tfstate"
    key               = "envs/govhigh/terraform.tfstate"
    region            = "us-gov-west-1"
    encrypt           = true
    kms_key_id        = "alias/foundry-govhigh-tfstate"
    dynamodb_table    = "foundry-govhigh-tf-locks"
    use_fips_endpoint = true
  }
}
