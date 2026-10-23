output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.eks_cluster.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS cluster certificate authority data"
  value       = aws_eks_cluster.eks_cluster.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version in use"
  value       = aws_eks_cluster.eks_cluster.version
}

output "service_listener_arns" {
  description = "Map of internal NLB listener ARNs indexed by bounded context"
  value       = { for k, v in aws_lb_listener.service : k => v.arn }
}

output "service_listener_ports" {
  description = "Map of internal NLB listener TCP ports indexed by bounded context"
  value       = { for k, v in local.services : k => v.listener_port }
}

output "nlb_dns_name" {
  description = "Internal DNS name of the NLB"
  value       = aws_lb.nlb_api.dns_name
}

output "smtp_listener_port" {
  description = "Internal NLB listener TCP port for MailHog SMTP"
  value       = local.smtp_listener_port
}

output "api_nlb_listener_arn" {
  description = "Transitional alias for service_listener_arns[\"work-order\"] until C-08 migrates the API Gateway"
  value       = aws_lb_listener.service["work-order"].arn
}

output "zz_next_steps" {
  description = "Post-deploy quick guide shown at the end of terraform output"
  value       = <<-EOT
  1) Set AWS credentials first
  Bash:
    export AWS_ACCESS_KEY_ID="<YOUR_ACCESS_KEY_ID>"
    export AWS_SECRET_ACCESS_KEY="<YOUR_SECRET_ACCESS_KEY>"
    export AWS_SESSION_TOKEN="<YOUR_SESSION_TOKEN>"
    export AWS_DEFAULT_REGION="${var.aws_region}"

  PowerShell:
    $Env:AWS_ACCESS_KEY_ID="<YOUR_ACCESS_KEY_ID>"
    $Env:AWS_SECRET_ACCESS_KEY="<YOUR_SECRET_ACCESS_KEY>"
    $Env:AWS_SESSION_TOKEN="<YOUR_SESSION_TOKEN>"
    $Env:AWS_DEFAULT_REGION="${var.aws_region}"

  2) Update kubeconfig for this cluster
    aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.eks_cluster.name}

  3) Validate kubectl access
    kubectl get nodes
  EOT
}
