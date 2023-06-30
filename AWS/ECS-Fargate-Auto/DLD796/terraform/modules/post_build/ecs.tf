
module "ecs_cluster" {
  source = "git@github.com:carmigo/infrastructure//modules/ecs/cluster"
  providers = {
    aws = aws.environment
  }

  name = local.name
  tags = local.tags
}

data "template_file" "definition" {
  template = file("${path.module}/task-def/def.json")
  vars = {
    region          = var.region
    log_group       = aws_cloudwatch_log_group.task_log_group.name
    image_tag       = var.image_tag
    definition_name = local.application_name
    datadog_secret  = var.datadog_secret
  }
  depends_on = [
    aws_cloudwatch_log_group.task_log_group
  ]
}


module "application_task_definition" {
  source = "git@github.com:carmigo/infrastructure//modules/ecs/task_definition"
  providers = {
    aws = aws.environment
  }

  name                  = local.application_name
  cpu                   = var.cpu
  memory                = var.memory
  task_role_arn         = var.task_role_arn
  container_definitions = jsondecode(data.template_file.definition.rendered)
  tags                  = merge(local.tags, local.application_tags)
  depends_on            = [module.ecs_cluster]
}


module "application_service" {
  source    = "git@github.com:carmigo/infrastructure//modules/ecs/service"
  providers = {
    aws = aws.environment
  }

  vpc_id                  = var.vpc_id
  ecs_cluster_id          = module.ecs_cluster.cluster_id
  name                    = local.application_name
  launch_type             = "FARGATE"
  desired_count           = 1
  task_definition_arn     = module.application_task_definition.task_definition_arn
  security_group_ids      = [module.security_group.id]

  tags = merge(local.tags, local.application_tags)

  depends_on = [module.application_task_definition, module.security_group]
}
