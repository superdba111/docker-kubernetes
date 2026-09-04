# -----------------------------------------------------------------------------
# EKS Cluster Add-on (CoreDNS)
# Note: CoreDNS is a Deployment, which requires worker nodes within the cluster.
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = var.coredns_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# -----------------------------------------------------------------------------
# EKS Cluster Add-on (kube-proxy)
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "kube-proxy" {
  cluster_name                = var.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube-proxy_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# -----------------------------------------------------------------------------
# EKS Cluster Add-on (Amazon VPC CNI)
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "vpc-cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc-cni_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    env : {
      WARM_ENI_TARGET : "0",
      MINIMUM_IP_TARGET : "5",
      WARM_IP_TARGET : "2"
    }
  })
}

# -----------------------------------------------------------------------------
# EKS Cluster Add-on (Amazon EBS CSI Driver)
# -----------------------------------------------------------------------------
# An IAM role which contains the permissions to manage EBS resources.
resource "aws_iam_role" "eks_ebs_driver_role" {
  name        = "AmazonEKS_EBS_CSI_DriverRole-${var.cluster_name}"
  description = "Allows EKS EBS CSI driver to manage EBS volumes."
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "OIDCAuthFromCluster",
        Effect : "Allow",
        Action : "sts:AssumeRoleWithWebIdentity",
        Principal : {
          Federated : var.cluster_oidc_provider_arn
        },
        Condition : {
          StringEquals : {
            "${var.cluster_oidc_provider}:aud" : "sts.amazonaws.com",
            "${var.cluster_oidc_provider}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

# EBS CSI Driver
resource "aws_eks_addon" "ebs-csi-driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs-csi-driver_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.eks_ebs_driver_role.arn
}

# -----------------------------------------------------------------------------
# EKS Cluster Add-on (Amazon EFS CSI Driver)
# -----------------------------------------------------------------------------
# An IAM role which contains the permissions to manage EFS resources.
resource "aws_iam_role" "eks_efs_driver_role" {
  name        = "AmazonEKS_EFS_CSI_DriverRole-${var.cluster_name}"
  description = "Allows EKS EFS CSI driver to manage EFS volumes."
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "OIDCAuthFromCluster",
        Effect : "Allow",
        Action : "sts:AssumeRoleWithWebIdentity",
        Principal : {
          Federated : var.cluster_oidc_provider_arn
        },
        Condition : {
          StringEquals : {
            "${var.cluster_oidc_provider}:aud" : "sts.amazonaws.com",
            "${var.cluster_oidc_provider}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

# EFS CSI Driver
resource "aws_eks_addon" "efs-csi-driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-efs-csi-driver"
  addon_version               = var.efs-csi-driver_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.eks_efs_driver_role.arn
}