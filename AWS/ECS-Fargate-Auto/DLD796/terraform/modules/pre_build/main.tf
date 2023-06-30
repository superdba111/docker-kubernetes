
# resource "aws_cloudwatch_log_group" "lamdba_cloudwatch_group" {
#   provider = aws.environment
#   name              = "/aws/lambda/${local.image_name}"
#   retention_in_days = 14
# }

