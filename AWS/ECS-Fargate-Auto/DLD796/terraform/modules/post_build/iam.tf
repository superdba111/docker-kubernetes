data "aws_caller_identity" "current" {}


resource "aws_iam_role" "service_role" {

  provider           = aws.environment
  name_prefix        = "service_role_"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
    EOF
}

data "aws_iam_policy" "task_execution" {

  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution" {

  provider = aws.environment

  role   = aws_iam_role.service_role.id
  name   = "AmazonECSTaskExecutionRolePolicy"
  policy = data.aws_iam_policy.task_execution.policy
}

resource "aws_iam_role" "task_role" {

  provider           = aws.environment
  name_prefix        = "task_role_"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
    EOF
}

resource "aws_iam_role_policy" "task_execution" {

  provider = aws.environment
  role     = aws_iam_role.task_role.id
  name     = "AmazonECSTaskExecutionRolePolicy"
  policy   = data.aws_iam_policy.task_execution.policy
}


resource "aws_iam_role" "scheduled_task_cloudwatch" {

  provider           = aws.environment
  name               = "${local.application_name}-cloudwatch-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "scheduled_task_cloudwatch_policy" {

  provider = aws.environment
  name     = "${local.application_name}-cloudwatch-policy"
  role     = aws_iam_role.scheduled_task_cloudwatch.id
  policy   = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RunTask"
      ],
      "Resource": [
        "${replace(module.application_task_definition.task_definition_arn, "/:\\d+$/", ":*")}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

