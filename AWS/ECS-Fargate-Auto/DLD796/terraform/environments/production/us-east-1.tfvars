// Environment variables
terraform_environment_name     = "reporting"
vpc_name                       = "reporting"
terraform_environment_region   = "us-east-1"
terraform_environment_iam_role = "arn:aws:iam::605516946663:role/Terraform"
account_id                     = "605516946663"
datadog_secret_arn             = "arn:aws:secretsmanager:us-east-1:605516946663:secret:datadog-Wt0BWG"
service_type                   = "jobs"
ecr_base                       = "711182801733.dkr.ecr.us-east-1.amazonaws.com"
processed_s3_bucket = "processed.datalake.reporting.e.inc"
landing_s3_bucket = "landing.datalake.reporting.e.inc"
published_s3_bucket = "published.datalake.reporting.e.inc"
 
// The following variables may be modified by the Data Scientist
image_name = "blackline-dw"
schedule   = "cron(0 7 * * ? *)"
cpu        = 1024
memory     = 2048
