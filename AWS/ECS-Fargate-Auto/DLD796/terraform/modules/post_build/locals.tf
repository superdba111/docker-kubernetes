locals {
  environment         = var.terraform_environment_name
  workspace           = var.terraform_workspace_name
  repository          = var.terraform_repository_name
  name                = var.terraform_workspace_name == "pull-request" ? format("%s-%s", var.image_name, var.terraform_workspace_branch) : var.image_name 
  # is_pull_request     = substr(var.terraform_workspace_branch, 0, 3) == "pr-"
  tags                = {
    Name        = local.name
    Environment = local.environment
    Workspace   = local.workspace
    Repository  = local.repository
    Branch      = var.terraform_workspace_branch
  }


  // "Application" service
  application_name      = format("%s-app", local.name) // Name should have workspace branch
  application_tags      = {
    Service = format("%s-app", local.repository) // Service should not have workspace branch
  }

}
