module "security_group" {
  source    = "git@github.com:carmigo/infrastructure//modules/security/security_group"
  providers = {
    aws = aws.environment
  }

  name        = format("%s-ecs-service", local.name)
  description = format("Security group for %s ECS Service", local.name)
  vpc_id      = var.vpc_id
  rules       = [
    {
      type        = "egress"
      description = "All egress HTTPS"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = merge(local.tags, local.application_tags)
}
