resource "aws_lb" "nlb_api" {
  name               = local.nlb_name
  internal           = true
  load_balancer_type = "network"
  subnets            = data.terraform_remote_state.aws_base.outputs.private_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = {
    Name = local.nlb_name
  }
}

resource "aws_lb_target_group" "service" {
  for_each = local.services

  name        = "tg-${var.project_name}-${each.key}"
  port        = each.value.node_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.terraform_remote_state.aws_base.outputs.vpc_id

  preserve_client_ip = false

  health_check {
    protocol            = "HTTP"
    path                = "/api/health/ready"
    port                = "traffic-port"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }

  tags = {
    Name = "tg-${var.project_name}-${each.key}"
  }
}

resource "aws_lb_listener" "service" {
  for_each = local.services

  load_balancer_arn = aws_lb.nlb_api.arn
  port              = each.value.listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[each.key].arn
  }
}

resource "aws_autoscaling_attachment" "service" {
  for_each = local.services

  autoscaling_group_name = aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.service[each.key].arn
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_service_node_port" {
  for_each = local.services

  description       = "Allow the internal NLB to reach the ${each.key} NodePort from within the VPC"
  security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  cidr_ipv4         = data.terraform_remote_state.aws_base.outputs.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = each.value.node_port
  to_port           = each.value.node_port

  tags = {
    Name = "sgr-${var.project_name}-${each.key}-node-port"
  }
}

resource "aws_lb_target_group" "smtp" {
  name        = local.tg_smtp_name
  port        = local.smtp_node_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.terraform_remote_state.aws_base.outputs.vpc_id

  preserve_client_ip = false

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = local.tg_smtp_name
  }
}

resource "aws_lb_listener" "smtp" {
  load_balancer_arn = aws_lb.nlb_api.arn
  port              = local.smtp_listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.smtp.arn
  }
}

resource "aws_autoscaling_attachment" "smtp" {
  autoscaling_group_name = aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.smtp.arn
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_smtp_node_port" {
  description       = "Allow the internal NLB to reach the MailHog SMTP NodePort from within the VPC"
  security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  cidr_ipv4         = data.terraform_remote_state.aws_base.outputs.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = local.smtp_node_port
  to_port           = local.smtp_node_port

  tags = {
    Name = "sgr-${var.project_name}-smtp-node-port"
  }
}
