module "pre_build" {
  source = "./modules/pre_build"
  providers = {
    aws.environment     = aws.environment
    aws.shared-services = aws.shared-services

  }

  // General configuration
  environment         = var.terraform_environment_name
  workspace           = var.terraform_workspace_name
  workspace_branch    = var.terraform_workspace_branch
  region              = var.terraform_environment_region
  project             = var.terraform_repository_name

  
  image_name          = var.image_name
  account_id          = var.account_id
  repository_name     = local.repository_name
  container_build     = var.container_build

}

output "pre_build" {
  value     = module.pre_build
  sensitive = false
}
