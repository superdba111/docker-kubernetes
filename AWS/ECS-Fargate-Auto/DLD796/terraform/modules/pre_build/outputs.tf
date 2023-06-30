
output "task_role_arn" {
  value = "${module.task_role.arn}"
}

output "base_ecr_url" {
  value = "${local.base_ecr_url}"
}

output "container_context" {
  value = "${local.container_context}"
}

output "container_build" {
  value = "${var.container_build}"
}
