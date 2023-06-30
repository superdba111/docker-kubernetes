locals {
   tags                = {
    Name        = local.application_name
    Environment = var.environment
    Workspace   = var.workspace
    Branch      = var.workspace_branch
    Project     = var.project
  }
  base_ecr_url      = format("%s/%s", var.image_name,local.workspace_branch)
  #container_context = format("%s/%s/%s", var.image_name,local.workspace_branch,var.image_name)
  container_context = format("%s/%s", var.image_name,local.workspace_branch)

  workspace_branch = var.workspace == "" ? "" : "${var.workspace_branch}"
  image_name       = var.workspace == "" ? var.image_name : format("%s-%s", var.image_name, var.workspace_branch)
  application_name = format("%s-app", local.image_name)

  terraform_shared_iam_role = "arn:aws:iam::711182801733:role/Terraform"

}
