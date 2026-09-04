# -----------------------------------------------------------------------------
# IAM Policy
# This policy grants read access to the EKS cluster.
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "eks_read_policy" {
  name        = "EKS-${var.cluster_name}-read-access"
  description = "Grants read permissions to the ${var.cluster_name} EKS cluster"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "EKSReadPermissions",
        Effect : "Allow",
        Action : [
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:ListTagsForResource",
          "eks:DescribeCluster"
        ]
        Resource : [
          "arn:aws:eks:${var.region}:${var.account_number}:cluster/${var.cluster_name}",
          "arn:aws:eks:${var.region}:${var.account_number}:nodegroup/${var.cluster_name}/*/*"
        ]
      },
      {
        Sid : "GlobalListPermission",
        Effect : "Allow",
        Action : "eks:ListClusters",
        Resource : "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Policy
# Retrieve existing S3 read/write policy (used for reporting/inventory).
# -----------------------------------------------------------------------------
data "aws_iam_policy" "s3_readwrite_policy" {
  arn = "arn:aws:iam::${var.account_number}:policy/mdl-admin-readwrite-s3"
}

# -----------------------------------------------------------------------------
# IAM Role
# This role will be used by the developer instance to grant command line access.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "developer_role" {
  name        = "eks-developer-${var.cluster_name}"
  description = "Used by RBAC to grant limited access to the EKS cluster."
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::011935884485:policy/NOAA-S3-Read-Scripts",
    aws_iam_policy.eks_read_policy.arn,
    data.aws_iam_policy.s3_readwrite_policy.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "GrantAccessToEC2",
        Effect : "Allow",
        Action : "sts:AssumeRole",
        Principal : {
          Service : "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Instance Profile
# When IAM roles are created through the AWS Console, both the role and
# an instance profile are created.
# In Terraform, we need to eplicitly create both.
# -----------------------------------------------------------------------------
resource "aws_iam_instance_profile" "developer_instance_profile" {
  name = "eks-developer-${var.cluster_name}"
  role = aws_iam_role.developer_role.name
}

# -----------------------------------------------------------------------------
# EC2 Instance
# This instance will be used by developers to access the cluster.
# -----------------------------------------------------------------------------
resource "aws_instance" "developer_instance" {
  ami                         = var.admin_instance_base_ami
  associate_public_ip_address = false
  credit_specification {
    cpu_credits = "standard"
  }
  disable_api_stop                     = false
  disable_api_termination              = true
  ebs_optimized                        = true
  get_password_data                    = false
  hibernation                          = false
  iam_instance_profile                 = aws_iam_instance_profile.developer_instance_profile.name
  instance_initiated_shutdown_behavior = "stop"
  instance_type                        = "t3.micro"
  monitoring                           = false
  root_block_device {
    delete_on_termination = true
    encrypted             = true
    iops                  = 3000
    kms_key_id            = "arn:aws:kms:${var.region}:${var.account_number}:key/${var.ebs_kms_key_id}"
    tags = {
      "Name" : "kubernetes-developers-${var.cluster_name}",
      "8872_NWS_Project" : var.nws_project_tag
    }
    throughput  = 125
    volume_size = 20
    volume_type = "gp3"
  }
  subnet_id = var.private_subnet_id
  tags = {
    "Name" : "kubernetes-developers-${var.cluster_name}",
    "8872_NWS_AutoPatch" : "True",
    "8872_NWS_PERSISTENCE_TYPE" : "PERMANENT",
    "8872_NWS_Project" : var.nws_project_tag,
    "8872_NWS_POC" : var.project_contacts
  }
  tenancy                     = "default"
  user_data_replace_on_change = false
  vpc_security_group_ids = [
    var.base_access_security_group_id
  ]
}