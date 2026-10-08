# Shared resources owned by the platform baseline stack.

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

locals {
  oidc_issuer   = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider = "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.oidc_issuer}"
}

# CMK for customer data at rest (SSE-KMS). Key policy managed in the baseline stack.
data "aws_kms_key" "customer_data" {
  key_id = "alias/foundry-govhigh-customer-data"
}

# Central S3 server access log bucket.
data "aws_s3_bucket" "access_logs" {
  bucket = "foundry-govhigh-s3-access-logs"
}

# Security group of the in-cluster ingress controller (portal ALB -> pods).
data "aws_security_group" "ingress_controller" {
  name   = "foundry-govhigh-ingress-controller"
  vpc_id = var.vpc_id
}
