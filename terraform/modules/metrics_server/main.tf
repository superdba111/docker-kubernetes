# -----------------------------------------------------------------------------
# Helm: Install the Kubernetes Metrics Server
# -----------------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  chart      = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  version    = var.metrics_server_helm_chart_version
  namespace  = "kube-system"
}