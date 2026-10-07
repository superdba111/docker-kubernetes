# Customer bulk data export — see docs/design/data-export.md

# Exports are derived from raw-ingest and can be regenerated, so they are not
# replicated. Any future DR copy must stay in GovCloud (444455556666 /
# us-gov-east-1); see authorization-boundary.md section 1.

# --- Bucket ---

resource "aws_s3_bucket" "exports" {
  bucket = "foundry-${var.environment}-customer-exports"
}

resource "aws_s3_bucket_versioning" "exports" {
  bucket = aws_s3_bucket.exports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "exports" {
  bucket = aws_s3_bucket.exports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = data.aws_kms_key.customer_data.arn
    }
    bucket_key_enabled = true
  }
}

# Downloads go through tenant-checked presigned URLs only; nothing is public.
resource "aws_s3_bucket_public_access_block" "exports" {
  bucket                  = aws_s3_bucket.exports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "exports" {
  bucket        = aws_s3_bucket.exports.id
  target_bucket = data.aws_s3_bucket.access_logs.id
  target_prefix = "customer-exports/"
}

# Exports are regenerable copies of raw-ingest data; keep them only as long as
# the customer needs to pull them.
resource "aws_s3_bucket_lifecycle_configuration" "exports" {
  bucket = aws_s3_bucket.exports.id
  rule {
    id     = "retention"
    status = "Enabled"
    filter {}
    expiration {
      days = 14
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "exports_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.exports.arn,
      "${aws_s3_bucket.exports.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "exports" {
  bucket = aws_s3_bucket.exports.id
  policy = data.aws_iam_policy_document.exports_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.exports]
}

# --- Job queue ---

resource "aws_kms_key" "exports" {
  description         = "export-service queue encryption"
  enable_key_rotation = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

resource "aws_sqs_queue" "export_jobs_dlq" {
  name              = "${var.environment}-export-jobs-dlq"
  kms_master_key_id = aws_kms_key.exports.arn
}

resource "aws_sqs_queue" "export_jobs" {
  name                       = "${var.environment}-export-jobs"
  kms_master_key_id          = aws_kms_key.exports.arn
  visibility_timeout_seconds = 900
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.export_jobs_dlq.arn
    maxReceiveCount     = 5
  })
}

# --- IRSA ---
#
# The API and the worker get separate service accounts and roles. The API is
# reachable from the portal and only needs to enqueue jobs and sign download
# URLs; it must not hold the worker's read access to every tenant's raw data.

locals {
  export_namespace = "exports"
  export_service_accounts = {
    api    = "export-api"
    worker = "export-worker"
  }
}

data "aws_iam_policy_document" "export_trust" {
  for_each = local.export_service_accounts

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${local.export_namespace}:${each.value}"]
    }
  }
}

resource "aws_iam_role" "export" {
  for_each           = local.export_service_accounts
  name               = "${var.environment}-${each.value}"
  assume_role_policy = data.aws_iam_policy_document.export_trust[each.key].json
}

# API: enqueue jobs; sign GET URLs for finished exports (the URL carries the
# signer's permissions, so it needs GetObject + Decrypt on the export objects).
data "aws_iam_policy_document" "export_api" {
  statement {
    sid       = "SignExportDownloads"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.exports.arn}/*"]
  }

  statement {
    sid       = "DecryptExports"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_key.customer_data.arn]
  }

  statement {
    sid       = "EnqueueJobs"
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.export_jobs.arn]
  }

  statement {
    sid       = "QueueKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.exports.arn]
  }
}

# Worker: consume the queue and nothing else directly. It has NO access to
# customer data. For each job it assumes the export-job role, tagging the
# session with the job's tenant, and processes the job with those credentials.
data "aws_iam_policy_document" "export_worker" {
  statement {
    sid = "ConsumeJobs"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.export_jobs.arn]
  }

  statement {
    sid       = "QueueKey"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.exports.arn]
  }

  statement {
    sid       = "AssumeTenantScopedJobRole"
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = [aws_iam_role.export_job.arn]
  }
}

# --- Per-job, tenant-scoped role (review B4) ---
#
# The session must carry exactly one tag, tenant_id, and every S3 permission is
# limited to that tenant's prefix through ${aws:PrincipalTag/tenant_id}.
# A bug in the worker can then only touch the job's tenant.
#
# Limits, recorded in review.md:
#   - Assumes raw-ingest keys are "<tenant_id>/..." (ingest-api is in another
#     repo; Ingest team to confirm). Exports are written as "<tenant_id>/...".
#   - The worker chooses the tag. It must take tenant_id from the DB job row,
#     not the SQS message. A fully compromised worker could still tag any
#     tenant; closing that needs a broker that issues the session per job.
#   - Role chaining caps sessions at 1 hour; longer jobs re-assume.

data "aws_iam_policy_document" "export_job_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.export["worker"].arn]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/tenant_id"
      values   = ["?*"]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["tenant_id"]
    }
  }
}

resource "aws_iam_role" "export_job" {
  name                 = "${var.environment}-export-job"
  assume_role_policy   = data.aws_iam_policy_document.export_job_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "export_job" {
  statement {
    sid       = "ReadTenantRaw"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.raw_ingest.arn}/$${aws:PrincipalTag/tenant_id}/*"]
  }

  statement {
    sid       = "ListTenantRaw"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.raw_ingest.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["$${aws:PrincipalTag/tenant_id}/*"]
    }
  }

  statement {
    sid       = "WriteTenantExports"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.exports.arn}/$${aws:PrincipalTag/tenant_id}/*"]
  }

  # With S3 bucket keys the KMS encryption context is the bucket, not the
  # object, so KMS can't be scoped per tenant; S3 statements above do that.
  # Restrict the key to use through S3 only.
  statement {
    sid       = "CustomerDataKeyViaS3"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [data.aws_kms_key.customer_data.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "export_job" {
  name   = "export-job"
  role   = aws_iam_role.export_job.id
  policy = data.aws_iam_policy_document.export_job.json
}

resource "aws_iam_role_policy" "export_api" {
  name   = "export-api"
  role   = aws_iam_role.export["api"].id
  policy = data.aws_iam_policy_document.export_api.json
}

resource "aws_iam_role_policy" "export_worker" {
  name   = "export-worker"
  role   = aws_iam_role.export["worker"].id
  policy = data.aws_iam_policy_document.export_worker.json
}

# --- Network ---
#
# This security group is attached to the export pods by the SecurityGroupPolicy
# in helm/charts/export-service (security groups for pods; needs the VPC CNI with
# ENABLE_POD_ENI=true, which Platform to confirm). Pass the output below to the
# chart as podSecurityGroup.groupIds.
#
# No internet egress, and no CIDR-wide rules (boundary section 5). Every rule
# names its destination:
#   - AWS APIs: the interface VPC endpoints for the FIPS hosts the SDK resolves
#     with AWS_USE_FIPS_ENDPOINT=true (checked with botocore 1.34):
#       s3  -> s3-fips.<region>  (needs the s3-fips interface endpoint; the S3
#                                  gateway endpoint does not serve the FIPS host)
#       sqs -> sqs.<region>      (GovCloud's standard SQS endpoint is FIPS)
#       sts -> sts.<region>      (IRSA web identity + worker job role)
#     KMS is called by S3/SQS on the service's behalf, not by the pods.
#   - In-cluster Sentry, portal JWKS, cluster DNS: the EKS cluster security group
#   - Postgres: the exports RDS cluster's security group
#
# The endpoints are looked up, not assumed: if any is missing (or lacks private
# DNS), terraform plan fails here instead of the service failing at runtime.

data "aws_vpc_endpoint" "export_service" {
  for_each = toset(["s3-fips", "sqs", "sts"])

  vpc_id       = var.vpc_id
  service_name = "com.amazonaws.${var.region}.${each.key}"
  state        = "available"

  lifecycle {
    postcondition {
      condition     = self.vpc_endpoint_type == "Interface" && self.private_dns_enabled
      error_message = "The ${each.key} VPC endpoint must be an Interface endpoint with private DNS, so the SDK's FIPS hostname resolves to it from the export pods."
    }
  }
}

locals {
  export_endpoint_security_group_ids = toset(flatten([
    for e in data.aws_vpc_endpoint.export_service : tolist(e.security_group_ids)
  ]))
  export_endpoint_eni_ids = toset(flatten([
    for e in data.aws_vpc_endpoint.export_service : tolist(e.network_interface_ids)
  ]))
}

# Endpoint ENI addresses, for the Kubernetes NetworkPolicy (which can't
# reference security groups). Output below; pass to the chart.
data "aws_network_interface" "export_endpoints" {
  for_each = local.export_endpoint_eni_ids
  id       = each.key
}

# Owned by the platform baseline. TODO(Platform): confirm this name; the
# convention follows data.aws_security_group.ingress_controller in data.tf.
data "aws_security_group" "exports_db" {
  name   = "foundry-${var.environment}-exports-db"
  vpc_id = var.vpc_id
}

locals {
  eks_cluster_security_group_id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_security_group" "export_service" {
  name   = "${var.environment}-export-service"
  vpc_id = var.vpc_id

  ingress {
    description     = "API from the ingress controller"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [data.aws_security_group.ingress_controller.id]
  }

  ingress {
    description     = "Kubelet readiness probes (nodes use the cluster SG)"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [local.eks_cluster_security_group_id]
  }

  egress {
    description     = "S3 (FIPS), SQS, STS via interface VPC endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = local.export_endpoint_security_group_ids
  }

  egress {
    description     = "In-cluster services: Sentry, portal JWKS"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [local.eks_cluster_security_group_id]
  }

  egress {
    description     = "Cluster DNS (TCP)"
    from_port       = 53
    to_port         = 53
    protocol        = "tcp"
    security_groups = [local.eks_cluster_security_group_id]
  }

  egress {
    description     = "Cluster DNS (UDP)"
    from_port       = 53
    to_port         = 53
    protocol        = "udp"
    security_groups = [local.eks_cluster_security_group_id]
  }

  egress {
    description     = "Exports RDS cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.aws_security_group.exports_db.id]
  }
}

# Security-group references only work if the destination also admits this
# group. Each rule below is the ingress half of an egress rule above. (Adding
# the cluster SG to the pods instead would also bring its allow-all egress and
# undo the narrowing.) These modify baseline-owned groups: Platform to review.

resource "aws_security_group_rule" "cluster_from_export_service" {
  for_each = {
    https   = { port = 443, protocol = "tcp", description = "Sentry, portal JWKS" }
    dns_tcp = { port = 53, protocol = "tcp", description = "Cluster DNS (TCP)" }
    dns_udp = { port = 53, protocol = "udp", description = "Cluster DNS (UDP)" }
  }

  type                     = "ingress"
  security_group_id        = local.eks_cluster_security_group_id
  source_security_group_id = aws_security_group.export_service.id
  from_port                = each.value.port
  to_port                  = each.value.port
  protocol                 = each.value.protocol
  description              = "export-service pods: ${each.value.description}"
}

resource "aws_security_group_rule" "vpc_endpoints_from_export_service" {
  for_each = local.export_endpoint_security_group_ids

  type                     = "ingress"
  security_group_id        = each.key
  source_security_group_id = aws_security_group.export_service.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  description              = "export-service pods: S3 (FIPS), SQS, STS"
}

resource "aws_security_group_rule" "exports_db_from_export_service" {
  type                     = "ingress"
  security_group_id        = data.aws_security_group.exports_db.id
  source_security_group_id = aws_security_group.export_service.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  description              = "export-service pods: Postgres"
}

output "export_service_security_group_id" {
  description = "Pass to the export-service chart as podSecurityGroup.groupIds."
  value       = aws_security_group.export_service.id
}

output "export_service_endpoint_cidrs" {
  description = "Interface endpoint addresses (s3-fips, sqs, sts). Pass to the export-service chart as networkPolicy.awsEndpointCidrs."
  value       = sort([for n in data.aws_network_interface.export_endpoints : "${n.private_ip}/32"])
}
