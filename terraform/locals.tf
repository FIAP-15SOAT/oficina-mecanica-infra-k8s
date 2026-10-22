locals {
  eks_cluster_name           = "eks-${var.project_name}"
  ecr_app_repo_name          = "ecr-${var.project_name}-app-repo"
  cw_lg_eks_cluster_tag_name = "cw-lg-eks-cluster-${var.project_name}"
  secgrp_eks_cluster_name    = "secgrp-eks-cluster-${var.project_name}"
  eks_node_group_name        = "ng-eks-${var.project_name}-default"
  nlb_name                   = "nlb-${var.project_name}"
  tg_work_order_name         = "tg-${var.project_name}-work-order"
}
