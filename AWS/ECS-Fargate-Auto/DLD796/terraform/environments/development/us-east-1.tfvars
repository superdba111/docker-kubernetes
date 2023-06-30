// Environment variables
terraform_environment_name     = "reporting-development"
vpc_name                       = "reporting-development"
terraform_environment_region   = "us-east-1"
terraform_environment_iam_role = "arn:aws:iam::292923181097:role/Terraform"
account_id                     = "292923181097"
datadog_secret_arn             = "arn:aws:secretsmanager:us-east-1:292923181097:secret:datadog-pXqhhS"
ecr_base                       = "711182801733.dkr.ecr.us-east-1.amazonaws.com"

// The following variables may be modified by the Data Scientist
image_name = "blackline-dw"

cpu        = 1024
memory     = 2048
