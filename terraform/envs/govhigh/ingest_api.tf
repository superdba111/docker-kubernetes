# ingest-api: receives line data from edge gateways and writes raw objects to S3.
# Reference implementation — reviewed and approved (SR-2026-031).

resource "aws_s3_bucket" "raw_ingest" {
  bucket = "foundry-${var.environment}-raw-ingest"
}

resource "aws_s3_bucket_versioning" "raw_ingest" {
  bucket = aws_s3_bucket.raw_ingest.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_ingest" {
  bucket = aws_s3_bucket.raw_ingest.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = data.aws_kms_key.customer_data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "raw_ingest" {
  bucket                  = aws_s3_bucket.raw_ingest.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "raw_ingest" {
  bucket        = aws_s3_bucket.raw_ingest.id
  target_bucket = data.aws_s3_bucket.access_logs.id
  target_prefix = "raw-ingest/"
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_ingest" {
  bucket = aws_s3_bucket.raw_ingest.id
  rule {
    id     = "retention"
    status = "Enabled"
    filter {}
    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
    expiration {
      days = 2555 # 7 years, contract retention
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

data "aws_iam_policy_document" "raw_ingest_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.raw_ingest.arn,
      "${aws_s3_bucket.raw_ingest.arn}/*",
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

resource "aws_s3_bucket_policy" "raw_ingest" {
  bucket = aws_s3_bucket.raw_ingest.id
  policy = data.aws_iam_policy_document.raw_ingest_tls_only.json
}

# --- IRSA ---

data "aws_iam_policy_document" "ingest_api_trust" {
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
      values   = ["system:serviceaccount:ingest:ingest-api"]
    }
  }
}

resource "aws_iam_role" "ingest_api" {
  name               = "${var.environment}-ingest-api"
  assume_role_policy = data.aws_iam_policy_document.ingest_api_trust.json
}

data "aws_iam_policy_document" "ingest_api" {
  statement {
    sid       = "WriteRaw"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.raw_ingest.arn}/*"]
  }
  statement {
    sid       = "UseCustomerDataKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [data.aws_kms_key.customer_data.arn]
  }
}

resource "aws_iam_role_policy" "ingest_api" {
  name   = "ingest-api"
  role   = aws_iam_role.ingest_api.id
  policy = data.aws_iam_policy_document.ingest_api.json
}
