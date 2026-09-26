# Customer bulk data export — see docs/design/data-export.md

variable "dr_exports_bucket_arn" {
  type        = string
  description = "Existing DR bucket in the commercial DR account (us-east-2)"
  default     = "arn:aws:s3:::foundry-dr-customer-exports"
}

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
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "exports" {
  bucket                  = aws_s3_bucket.exports.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false # required for portal preview policy below
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "exports_bucket" {
  statement {
    sid       = "PortalPreviews"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.exports.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:Referer"
      values   = ["https://portal.foundry-gov.example/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "exports" {
  bucket = aws_s3_bucket.exports.id
  policy = data.aws_iam_policy_document.exports_bucket.json
}

# --- DR replication ---

data "aws_iam_policy_document" "replication_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "exports_replication" {
  name               = "${var.environment}-exports-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_trust.json
}

data "aws_iam_policy_document" "exports_replication" {
  statement {
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.exports.arn]
  }
  statement {
    actions   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl"]
    resources = ["${aws_s3_bucket.exports.arn}/*"]
  }
  statement {
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete"]
    resources = ["${var.dr_exports_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "exports_replication" {
  name   = "exports-replication"
  role   = aws_iam_role.exports_replication.id
  policy = data.aws_iam_policy_document.exports_replication.json
}

resource "aws_s3_bucket_replication_configuration" "exports_dr" {
  depends_on = [aws_s3_bucket_versioning.exports]
  role       = aws_iam_role.exports_replication.arn
  bucket     = aws_s3_bucket.exports.id

  rule {
    id     = "dr-copy"
    status = "Enabled"
    filter {}
    delete_marker_replication {
      status = "Enabled"
    }
    destination {
      bucket        = var.dr_exports_bucket_arn
      storage_class = "STANDARD_IA"
    }
  }
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
      test     = "StringLike"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:*:export-service"]
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
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::foundry-govhigh-customer-exports",
      "arn:aws:s3:::foundry-govhigh-customer-exports/*",
    ]
  }

  statement {
    sid       = "ReadRawIngest"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::foundry-govhigh-raw-ingest", "arn:aws:s3:::foundry-govhigh-raw-ingest/*"]
  }

  statement {
    sid     = "Kms"
    actions = ["kms:Decrypt", "kms:GenerateDataKey", "kms:Encrypt"]
    # TODO(DP-2297): scope down — scoped key ARN was denied in staging
    resources = ["*"]
  }

  statement {
    sid       = "Queue"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.export_jobs.arn, aws_sqs_queue.export_jobs_dlq.arn]
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
