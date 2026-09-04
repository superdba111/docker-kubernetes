# -----------------------------------------------------------------------------
# Namespace
# Create the "vlab" namespace.
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "vlab_namespace" {
  metadata {
    name = "vlab"
  }
}