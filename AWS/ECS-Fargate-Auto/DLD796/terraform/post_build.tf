module "post_build" {
  source = "./modules/post_build"
  providers = {
    aws.environment = aws.environment
  }

  // General configuration
  vpc_id                     = data.aws_vpc.this.id
  subnet_ids                 = data.aws_subnets.subnets.ids
  terraform_environment_name = var.terraform_environment_name
  terraform_workspace_name   = var.terraform_workspace_name
  terraform_repository_name  = var.terraform_repository_name
  terraform_workspace_branch = var.terraform_workspace_branch
  region                     = var.terraform_environment_region
  image_tag                  = "${var.ecr_base}/${local.repository_name}:${var.container_version}"
  task_role_arn              = module.pre_build.task_role_arn
  schedule                   = var.schedule
  image_name                 = var.image_name
  cpu                        = var.cpu
  memory                     = var.memory
  datadog_secret             = module.datadog_secret.secret_value["api_key"]

  depends_on = [
    module.pre_build
  ]
}

output "post_build" {
  value     = module.post_build
  sensitive = false
}
