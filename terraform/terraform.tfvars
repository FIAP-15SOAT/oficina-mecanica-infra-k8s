aws_region   = "us-east-1"
project_name = "oficina-mecanica"
environment  = "prod-simulated"

kubernetes_version = "1.35"
node_instance_type = "t3.medium"
node_desired_size  = 1
node_min_size      = 1
node_max_size      = 1

aws_base_state_key    = "infra/prod-simulated/infra-base/terraform.tfstate"
aws_base_state_region = "us-east-1"

k8s_namespace = "oficina"

enable_metrics_server        = true
metrics_server_chart_version = "3.13.0"

api_node_port = 30080
