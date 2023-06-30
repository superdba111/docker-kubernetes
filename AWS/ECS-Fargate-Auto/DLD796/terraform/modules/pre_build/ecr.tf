module "ecr_model" {
  source = "git@github.com:carmigo/infrastructure//modules/ecr?ref=add-ecr-policy-with-interpolated-local-policy"
  providers = {
    aws = aws.shared-services
  }
  enable_vulnerability_scanning = false
  repository_name = var.repository_name

  tags            = local.tags
}

data "aws_organizations_organization" "current" {}




