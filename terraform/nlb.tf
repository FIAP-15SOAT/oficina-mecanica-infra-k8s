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

resource "aws_lb_target_group" "tg_api" {
  name        = local.tg_work_order_name
  port        = var.api_node_port
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
    Name = local.tg_work_order_name
  }
}

resource "aws_lb_listener" "nlb_api_listener" {
  load_balancer_arn = aws_lb.nlb_api.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_api.arn
  }
}

resource "aws_autoscaling_attachment" "asg_api_tg" {
  autoscaling_group_name = aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.tg_api.arn
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_api_node_port" {
  description       = "Allow the internal API NLB to reach the API NodePort from within the VPC"
  security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  cidr_ipv4         = data.terraform_remote_state.aws_base.outputs.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = var.api_node_port
  to_port           = var.api_node_port

  tags = {
    Name = "sgr-${var.project_name}-work-order-node-port"
  }
}
