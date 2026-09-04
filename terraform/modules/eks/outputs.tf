# -----------------------------------------------------------------------------
# Output values from this module.
# -----------------------------------------------------------------------------
output "cluster_api_server_endpoint" {
  value = aws_eks_cluster.cluster.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.cluster.certificate_authority[0].data
}

output "cluster_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.cluster_oidc.arn
}

output "cluster_oidc_provider" {
  value = replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
}

output "cluster_node_role_arn" {
  value = aws_iam_role.eks_node_role.arn
}