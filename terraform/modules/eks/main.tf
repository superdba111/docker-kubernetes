# -----------------------------------------------------------------------------
# IAM Role
# The EKS cluster IAM role.
# NOTE: Included "ElasticLoadBalancingFullAccess" policy per request from Maxwell.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "eks_cluster_service_role" {
  name        = "KubernetesClusterRole-${var.cluster_name}"
  description = "Allows EKS to call other AWS services"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
  ]
  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Sid : "GrantAccessToEKS"
        Effect : "Allow",
        Action : "sts:AssumeRole",
        Principal : {
          Service : "eks.amazonaws.com"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Role
# This role is assigned to EC2 worker nodes within the EKS cluster.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "eks_node_role" {
  name        = "AmazonEKSNodeRole-${var.cluster_name}"
  description = "IAM role assigned to nodes in the EKS cluster"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::011935884485:policy/NOAA-S3-Read-Scripts"
  ]
  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Sid : "GrantAccessToEC2"
        Effect : "Allow",
        Action : "sts:AssumeRole",
        Principal : {
          Service : ["ec2.amazonaws.com", "glue.amazonaws.com"]
        }
      }
    ]
  })
}

# Instance profile for this IAM role.
resource "aws_iam_instance_profile" "eks_node_instance_profile" {
  name = "AmazonEKSNodeRole-${var.cluster_name}"
  role = aws_iam_role.eks_node_role.name
}

# -----------------------------------------------------------------------------
# KMS Key
# Used for encryption within the EKS cluster.
# -----------------------------------------------------------------------------
resource "aws_kms_key" "cluster_key" {
  description              = "Used for Kubernetes Secrets encryption in EKS."
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Sid : "Default",
        Effect : "Allow",
        Principal : {
          AWS : "arn:aws:iam::${var.account_number}:root"
        },
        Action : "kms:*",
        Resource : "*"
      },
      {
        Sid : "KeyAdministration",
        Effect : "Allow",
        Principal : {
          AWS : "arn:aws:iam::${var.account_number}:role/VLabCloudAdmin"
        },
        Action : [
          "kms:Update*",
          "kms:UntagResource",
          "kms:TagResource",
          "kms:ScheduleKeyDeletion",
          "kms:Revoke*",
          "kms:Put*",
          "kms:List*",
          "kms:Get*",
          "kms:Enable*",
          "kms:Disable*",
          "kms:Describe*",
          "kms:Delete*",
          "kms:Create*",
          "kms:CancelKeyDeletion"
        ],
        Resource : "*"
      },
      {
        Sid : "KeyUsage",
        Effect : "Allow",
        Principal : {
          AWS : aws_iam_role.eks_cluster_service_role.arn
        },
        Action : [
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Encrypt",
          "kms:DescribeKey",
          "kms:Decrypt"
        ],
        Resource : "*"
      },
    ]
  })
  enable_key_rotation = false
  multi_region        = false
}

# -----------------------------------------------------------------------------
# Security Group
# An additional security group that will be applied to the EKS cluster.
# Grants kubectl access to the admin EC2 instance.
# -----------------------------------------------------------------------------
resource "aws_security_group" "allow_admin_instance" {
  name        = "${var.cluster_name}-AllowInstanceTraffic"
  description = "Allows cluster access from the admin and developer instances."
  vpc_id      = var.vpc_id
  ingress {
    description = "Allow HTTPS from admin instance"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${var.admin_instance_private_ip}/32"]
  }
  ingress {
    description = "Allow HTTPS from developer instance"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${var.developer_instance_private_ip}/32"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------
resource "aws_eks_cluster" "cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_service_role.arn
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = [var.mdl_prod_nat_ip_address]
    security_group_ids      = [aws_security_group.allow_admin_instance.id]
    subnet_ids = [
      var.private_subnet_1a_id,
      var.private_subnet_1b_id
    ]
  }
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
  encryption_config {
    provider {
      key_arn = aws_kms_key.cluster_key.arn
    }
    resources = ["secrets"]
  }
  kubernetes_network_config {
    service_ipv4_cidr = "172.16.0.0/12"
    ip_family         = "ipv4"
  }
  version = var.cluster_version
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# Logging is enabled in the cluster configuration above.
# Modify the log group's retention period.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "cluster_log_group" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30
}

# -----------------------------------------------------------------------------
# Cluster OIDC Setup
# -----------------------------------------------------------------------------
data "tls_certificate" "cluster_cert" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster_cert.certificates[0].sha1_fingerprint]
  url             = data.tls_certificate.cluster_cert.url
}