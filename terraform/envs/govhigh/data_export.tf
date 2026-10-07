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

data "aws_iam_policy_document" "export_service_trust" {
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
      values   = ["system:serviceaccount:exports:export-service"]
    }
  }
}

resource "aws_iam_role" "export_service" {
  name               = "${var.environment}-export-service"
  assume_role_policy = data.aws_iam_policy_document.export_service_trust.json
}

data "aws_iam_policy_document" "export_service" {
  statement {
    sid = "Exports"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.exports.arn}/*"]
  }

  statement {
    sid       = "ListExports"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.exports.arn]
  }

  # TODO(DP-2297 follow-up): limit to the job's tenant prefix once the worker
  # code is in review; see review/review.md B4.
  statement {
    sid       = "ReadRawIngest"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.raw_ingest.arn, "${aws_s3_bucket.raw_ingest.arn}/*"]
  }

  # raw-ingest and customer-exports are both SSE-KMS with the customer-data CMK.
  # Missing this grant is what caused the staging AccessDenied, not the scope.
  statement {
    sid       = "CustomerDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [data.aws_kms_key.customer_data.arn]
  }

  statement {
    sid       = "QueueKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.exports.arn]
  }

  statement {
    sid = "Queue"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.export_jobs.arn]
  }
}

resource "aws_iam_role_policy" "export_service" {
  name   = "export-service"
  role   = aws_iam_role.export_service.id
  policy = data.aws_iam_policy_document.export_service.json
}

# --- Network (attached to pods via SecurityGroupPolicy) ---

resource "aws_security_group" "export_service" {
  name   = "${var.environment}-export-service"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [data.aws_security_group.ingress_controller.id]
  }

  egress {
    description = "S3, SQS, Sentry"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "RDS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.40.0.0/16"]
  }
}
