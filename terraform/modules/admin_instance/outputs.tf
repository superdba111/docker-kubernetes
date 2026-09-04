# -----------------------------------------------------------------------------
# Output values from this module.
# -----------------------------------------------------------------------------
output "private_ip" {
  value = aws_instance.admin_instance.private_ip
}

output "admin_instance_role_arn" {
  value = aws_iam_role.admin_role.arn
}