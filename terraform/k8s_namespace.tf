resource "kubernetes_namespace_v1" "k8s_namespace" {
  for_each = local.namespaces

  metadata {
    name = each.key

    labels = {
      "app.kubernetes.io/part-of" = var.project_name
      "managed-by"                = "terraform"
    }
  }

  depends_on = [aws_eks_node_group.eks_node_group]
}
