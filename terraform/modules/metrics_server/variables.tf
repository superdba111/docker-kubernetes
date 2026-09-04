# -----------------------------------------------------------------------------
# Input variables for this module.
# -----------------------------------------------------------------------------
variable "metrics_server_helm_chart_version" {
  type        = string
  description = "The version of the Kubernetes Metrics Server Helm chart to install."
  nullable    = false
}