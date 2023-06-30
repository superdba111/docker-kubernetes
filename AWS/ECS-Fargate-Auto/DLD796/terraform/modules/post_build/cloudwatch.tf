resource "aws_cloudwatch_log_group" "task_log_group" {
provider = aws.environment
  retention_in_days = 1
  name_prefix       = "${local.application_name}-"
}

resource "aws_cloudwatch_event_rule" "scheduled_task" {
provider = aws.environment

  name                = "${local.application_name}-event-rule"
  schedule_expression = var.schedule // https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html#CronExpressions
  is_enabled          = true             // Change to true to enable scheduling
}

resource "aws_cloudwatch_event_target" "scheduled_task" {
provider = aws.environment

  target_id = "${local.application_name}-target"
  rule      = aws_cloudwatch_event_rule.scheduled_task.name
  arn       = module.ecs_cluster.cluster_arn
  role_arn  = aws_iam_role.scheduled_task_cloudwatch.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = module.application_task_definition.task_definition_arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = var.subnet_ids
      assign_public_ip = true
      security_groups  = [module.security_group.id]
    }
  }
}