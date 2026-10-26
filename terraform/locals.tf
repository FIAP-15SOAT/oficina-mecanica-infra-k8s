locals {
  eks_cluster_name           = "eks-${var.project_name}"
  cw_lg_eks_cluster_tag_name = "cw-lg-eks-cluster-${var.project_name}"
  secgrp_eks_cluster_name    = "secgrp-eks-cluster-${var.project_name}"
  eks_node_group_name        = "ng-eks-${var.project_name}-default"
  nlb_name                   = "nlb-${var.project_name}"
  tg_smtp_name               = "tg-${var.project_name}-smtp"

  services = {
    work-order = {
      node_port     = 30080
      listener_port = 80
    }
    identity = {
      node_port     = 30081
      listener_port = 8081
    }
    billing = {
      node_port     = 30082
      listener_port = 8082
    }
    inventory = {
      node_port     = 30083
      listener_port = 8083
    }
  }

  namespaces = toset(concat(keys(local.services), ["platform"]))

  smtp_node_port     = 31025
  smtp_listener_port = 1025
}
