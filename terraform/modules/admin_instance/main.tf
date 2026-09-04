# -----------------------------------------------------------------------------
# IAM Policy
# This policy grants EKS permissions.
# Most permissions are restricted to a given cluster.
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "eks_policy" {
  name        = "EKS-Admin-FullAccess-Policy-${var.cluster_name}"
  description = "Grants permission to create and fully manage an EKS cluster."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "GlobalPermissions",
        Effect : "Allow",
        Action : [
          "eks:DescribeAddonConfiguration",
          "eks:ListClusters",
          "eks:DescribeAddonVersions",
          "eks:RegisterCluster",
          "eks:CreateCluster"
        ]
        Resource : "*"
      },
      {
        Sid : "ClusterPermissions",
        Effect : "Allow",
        Action : [
          "eks:DeleteFargateProfile",
          "eks:UpdateClusterVersion",
          "eks:DescribeFargateProfile",
          "eks:ListTagsForResource",
          "eks:UpdateAddon",
          "eks:ListAddons",
          "eks:UpdateClusterConfig",
          "eks:DescribeAddon",
          "eks:UpdateNodegroupVersion",
          "eks:DescribeNodegroup",
          "eks:AssociateEncryptionConfig",
          "eks:ListUpdates",
          "eks:ListIdentityProviderConfigs",
          "eks:ListNodegroups",
          "eks:DisassociateIdentityProviderConfig",
          "eks:UntagResource",
          "eks:CreateNodegroup",
          "eks:DeregisterCluster",
          "eks:DeleteCluster",
          "eks:CreateFargateProfile",
          "eks:ListFargateProfiles",
          "eks:DescribeIdentityProviderConfig",
          "eks:DeleteAddon",
          "eks:DeleteNodegroup",
          "eks:DescribeUpdate",
          "eks:TagResource",
          "eks:AccessKubernetesApi",
          "eks:CreateAddon",
          "eks:UpdateNodegroupConfig",
          "eks:DescribeCluster",
          "eks:AssociateIdentityProviderConfig"
        ],
        Resource : [
          "arn:aws:eks:${var.region}:${var.account_number}:identityproviderconfig/${var.cluster_name}/*/*/*",
          "arn:aws:eks:${var.region}:${var.account_number}:fargateprofile/${var.cluster_name}/*/*",
          "arn:aws:eks:${var.region}:${var.account_number}:nodegroup/${var.cluster_name}/*/*",
          "arn:aws:eks:${var.region}:${var.account_number}:cluster/${var.cluster_name}",
          "arn:aws:eks:${var.region}:${var.account_number}:addon/${var.cluster_name}/*/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Policy
# This policy grants necessary permissions to IAM.
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "iam_policy" {
  name        = "EKS-Admin-IAM-Policy-${var.cluster_name}"
  description = "Grants necessary permissions to IAM."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "ListOIDCProviders",
        Effect : "Allow",
        Action : "iam:ListOpenIDConnectProviders",
        Resource : "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Policy
# This policy grants full access to the account's ECR service.
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "ecr_policy" {
  name        = "EKS-Admin-ECR-Policy-${var.cluster_name}"
  description = "Grants full access to ECR."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "ECRPermissions",
        Effect : "Allow",
        Action : [
          "ecr:DescribeImageScanFindings",
          "ecr:GetLifecyclePolicyPreview",
          "ecr:GetDownloadUrlForLayer",
          "ecr:ListTagsForResource",
          "ecr:UploadLayerPart",
          "ecr:BatchDeleteImage",
          "ecr:ListImages",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:InitiateLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetRepositoryPolicy",
          "ecr:GetLifecyclePolicy",
          "ecr:GetAuthorizationToken"
        ]
        Resource : "arn:aws:ecr:${var.region}:${var.account_number}:repository/*"
      },
      {
        Sid : "ECRGlobalPermissions",
        Effect : "Allow",
        Action : "ecr:GetAuthorizationToken",
        Resource : "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Policy
# This policy grants the administrator role read/write permissions
# to the dev VLab Helm chart repo.
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "helm_policy" {
  # (Optional) The name of the policy.
  name = "EKS-Admin-VLab-Helm-Policy-${var.cluster_name}"
  # (Optional) The description for the policy.
  description = "Grants read and write permissions to the project's chart repo."
  # (Optional) Creates a unique name for the policy with the given prefix.
  name_prefix = null
  # (Optional) The path in which to create the policy.
  path = null
  # (Required) The policy document.
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "ProgrammaticReadAccess",
        Effect : "Allow",
        Action : "s3:ListBucket",
        Resource : "arn:aws:s3:::${var.helm_chart_repo}"
      },
      {
        Sid : "S3WritePermissions",
        Effect : "Allow",
        Action : [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ],
        Resource : "arn:aws:s3:::${var.helm_chart_repo}/*"
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
# A role for managing an EKS cluster.
# NOTE: Include "AdministratorAccess" policy per request from Maxwell.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "admin_role" {
  name        = "eks-admin-${var.cluster_name}"
  description = "Grants full permission to modify the EKS cluster."
  managed_policy_arns = [
    aws_iam_policy.eks_policy.arn,
    aws_iam_policy.iam_policy.arn,
    aws_iam_policy.ecr_policy.arn,
    aws_iam_policy.helm_policy.arn,
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    data.aws_iam_policy.s3_readwrite_policy.arn,
    "arn:aws:iam::aws:policy/AdministratorAccess"
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
resource "aws_iam_instance_profile" "admin_instance_profile" {
  name = "eks-admin-${var.cluster_name}"
  role = aws_iam_role.admin_role.name
}

# -----------------------------------------------------------------------------
# EC2 Instance
# This instance will be used to administer the EKS cluster.
# -----------------------------------------------------------------------------
resource "aws_instance" "admin_instance" {
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
  iam_instance_profile                 = aws_iam_instance_profile.admin_instance_profile.name
  instance_initiated_shutdown_behavior = "stop"
  instance_type                        = "t3.micro"
  monitoring                           = false
  root_block_device {
    delete_on_termination = true
    encrypted             = true
    iops                  = 3000
    kms_key_id            = "arn:aws:kms:${var.region}:${var.account_number}:key/${var.ebs_kms_key_id}"
    tags = {
      "Name" : "kubernetes-admin-${var.cluster_name}",
      "8872_NWS_Project" : var.nws_project_tag
    }
    throughput  = 125
    volume_size = 20
    volume_type = "gp3"
  }
  subnet_id = var.private_subnet_id
  tags = {
    "Name" : "kubernetes-admin-${var.cluster_name}",
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