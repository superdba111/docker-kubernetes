# -----------------------------------------------------------------------------
# Output values from this module.
# -----------------------------------------------------------------------------
output "private_ip" {
  value = aws_instance.developer_instance.private_ip
}

output "developer_instance_role_arn" {
  value = aws_iam_role.developer_role.arn
}