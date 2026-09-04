# -----------------------------------------------------------------------------
# aws-auth ConfigMap
# Maps Kubernetes RBAC permissions to IAM principals.
# -----------------------------------------------------------------------------
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  data = {
    mapRoles = <<YAML
    - rolearn: ${var.cluster_node_role_arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    - rolearn: arn:aws:iam::${var.account_number}:role/VLabCloudAdmin
      username: admin
      groups:
        - system:masters
    - rolearn: ${var.admin_instance_role_arn}
      username: admin
      groups:
        - system:masters
    - rolearn: ${var.developer_instance_role_arn}
      username: developer
      groups:
        - eks-console-dashboard-full-access-group
        - vlab-elevated-permissions
    YAML
  }
}

# -----------------------------------------------------------------------------
# ClusterRole
# Grants read access to a wide range of resources across the cluster.
# -----------------------------------------------------------------------------
resource "kubernetes_cluster_role" "read_cluster_role" {
  metadata {
    name = "eks-console-dashboard-full-access-clusterrole"
  }
  rule {
    api_groups = [""]
    resources  = ["nodes", "namespaces", "pods", "configmaps", "endpoints", "events", "limitranges", "persistentvolumes", "persistentvolumeclaims", "podtemplates", "replicationcontrollers", "resourcequotas", "secrets", "serviceaccounts", "services"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "daemonsets", "statefulsets", "replicasets"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["events.k8s.io"]
    resources  = ["events"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["extensions"]
    resources  = ["daemonsets", "deployments", "ingresses", "networkpolicies", "replicasets"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["rolebindings", "roles"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["csistoragecapacities"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["elbv2.k8s.aws"]
    resources  = ["targetgroupbindings"]
    verbs      = ["get", "list"]
  }
}

# -----------------------------------------------------------------------------
# ClusterRoleBinding
# Maps the ClusterRole "read_cluster_role" to the group
# "eks-console-dashboard-full-access-group"
# -----------------------------------------------------------------------------
resource "kubernetes_cluster_role_binding" "read_cluster_role_binding" {
  metadata {
    name = "eks-console-dashboard-full-access-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "eks-console-dashboard-full-access-clusterrole"
  }
  subject {
    kind      = "Group"
    name      = "eks-console-dashboard-full-access-group"
    api_group = "rbac.authorization.k8s.io"
  }
}

# -----------------------------------------------------------------------------
# Role
# Grants elevated privileges to the vlab namespace.
# -----------------------------------------------------------------------------
resource "kubernetes_role" "vlab_elevated_role" {
  metadata {
    name      = "vlab-elevated-permissions"
    namespace = "vlab"
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "configmaps", "endpoints", "events", "limitranges", "persistentvolumeclaims", "podtemplates", "replicationcontrollers", "resourcequotas", "secrets", "serviceaccounts", "services"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "daemonsets", "statefulsets", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["events.k8s.io"]
    resources  = ["events"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["extensions"]
    resources  = ["daemonsets", "deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list"]
  }
}

# -----------------------------------------------------------------------------
# RoleBinding
# Maps the Role "vlab-elevated-permissions" to the group
# "vlab-elevated-permissions"
# -----------------------------------------------------------------------------
resource "kubernetes_role_binding" "vlab_elevated_role_binding" {
  metadata {
    name      = "vlab-elevated-permissions"
    namespace = "vlab"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "vlab-elevated-permissions"
  }
  subject {
    kind      = "Group"
    name      = "vlab-elevated-permissions"
    api_group = "rbac.authorization.k8s.io"
  }
}