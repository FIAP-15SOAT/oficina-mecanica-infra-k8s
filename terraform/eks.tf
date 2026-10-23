data "aws_iam_role" "eks_cluster_iam_role" {
  name = var.eks_cluster_role_name
}

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

resource "aws_cloudwatch_log_group" "cw_lg_eks_cluster" {
  name              = "/aws/eks/${local.eks_cluster_name}/cluster"
  retention_in_days = 14

  tags = {
    Name = local.cw_lg_eks_cluster_tag_name
  }
}

resource "aws_security_group" "secgrp_eks_cluster" {
  name        = local.secgrp_eks_cluster_name
  description = "Security group for EKS control plane"
  vpc_id      = data.terraform_remote_state.aws_base.outputs.vpc_id

  ingress {
    description = "Allow HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.terraform_remote_state.aws_base.outputs.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = local.secgrp_eks_cluster_name
  }
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = local.eks_cluster_name
  role_arn = data.aws_iam_role.eks_cluster_iam_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(data.terraform_remote_state.aws_base.outputs.private_subnet_ids, data.terraform_remote_state.aws_base.outputs.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.secgrp_eks_cluster.id]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = {
    Name = "eks-${var.project_name}"
  }

  depends_on = [
    aws_cloudwatch_log_group.cw_lg_eks_cluster
  ]
}

resource "aws_launch_template" "eks_nodes" {
  name_prefix   = "lt-eks-${var.project_name}-nodes-"
  description   = "Launch template for EKS worker nodes with IMDSv2 hop limit 2 and node identity SG"
  instance_type = var.node_instance_type

  vpc_security_group_ids = [
    aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id,
    data.terraform_remote_state.aws_base.outputs.eks_nodes_security_group_id,
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = local.eks_node_group_name
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Name        = local.eks_node_group_name
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }

  tags = {
    Name = "lt-eks-${var.project_name}-nodes"
  }
}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = local.eks_node_group_name
  node_role_arn   = data.aws_iam_role.lab_role.arn
  subnet_ids      = data.terraform_remote_state.aws_base.outputs.private_subnet_ids

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  tags = {
    Name = local.eks_node_group_name
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}
