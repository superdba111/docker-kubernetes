


resource "aws_iam_policy" "ecs_ssh_access" {
provider = aws.environment
  name        = format("%s-ecr-ssh-access", local.application_name)
  path        = "/"
  description = "Allows ECS to SSH into Container via SSM"
  policy      = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
          "kms:Decrypt"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

data "aws_kms_alias" "ssm" {
  name = "alias/ssm"
}

data "aws_kms_alias" "secretsmanager" {
  name = "alias/secretsmanager"
}

resource "aws_iam_policy" "ecs_secrets_access" {
  provider = aws.environment
  name        = format("%s-ecr-access-secrets", local.application_name)
  path        = "/"
  description = "Allows ECS to read Secrets from Secrets Manager and Systems Manager Parameter Store"
  policy      = <<POLICY
{
	"Version": "2012-10-17",
	"Statement": [{
			"Effect": "Allow",
			"Action": [
				"secretsmanager:GetSecretValue",
				"ssm:GetParameters"
			],
			"Resource": "*"
		},
		{
			"Effect": "Allow",
			"Action": [
				"kms:Decrypt",
				"kms:GenerateDataKey",
				"kms:GenerateDataKeyPair"
			],
			"Resource": [
				"${data.aws_kms_alias.secretsmanager.target_key_arn}",
				"${data.aws_kms_alias.ssm.target_key_arn}"
			]
		},
		{
			"Effect": "Allow",
			"Action": [
				"secretsmanager:GetSecretValue",
				"kms:GenerateDataKey",
				"ssm:GetParameters",
				"kms:GenerateDataKeyPair"
			],
			"Resource": "*"
		}
	]
}
POLICY
}

module "task_role" {
  source = "git@github.com:carmigo/infrastructure//modules/iam/role"
   providers = {
    aws = aws.environment
  }

  name             = format("%s-ecs-task", local.application_name)
  description      = "IAM Role used by ECS task"
  actions          = ["sts:AssumeRole"]
  identifier_type  = "Service"
  identifiers      = ["ecs-tasks.amazonaws.com"]
  role_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",
    "arn:aws:iam::aws:policy/AWSAppMeshPreviewEnvoyAccess",
    "arn:aws:iam::aws:policy/AWSAppMeshEnvoyAccess",
    aws_iam_policy.ecs_ssh_access.arn,
    aws_iam_policy.ecs_secrets_access.arn
  ]

  tags =  {
    Name       = format("%s-ecs-task", local.application_name)
    NamePrefix = local.application_name

  }
}