// Environment variables
terraform_environment_name     = "reporting-pr"
vpc_name                       = "reporting-development"
terraform_environment_region   = "us-east-1"
terraform_environment_iam_role = "arn:aws:iam::292923181097:role/Terraform"
account_id                     = "292923181097"
datadog_secret_arn             = "arn:aws:secretsmanager:us-east-1:292923181097:secret:datadog-pXqhhS"
service_type                   = "jobs"
ecr_base                       = "711182801733.dkr.ecr.us-east-1.amazonaws.com"
processed_s3_bucket = "processed.datalake.reporting-dev.e.inc"
landing_s3_bucket = "landing.datalake.reporting-dev.e.inc"
published_s3_bucket = "published.datalake.reporting-dev.e.inc"

// The following variables may be modified by the Data Scientist
image_name = "blackline-dw"
schedule   = "cron(0 */4 * * ? *)"
cpu        = 1024
memory     = 2048
