variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Base project name used for resource tags"
  type        = string
  default     = "oficina-mecanica"
}

variable "environment" {
  description = "Environment name used for default tagging"
  type        = string
  default     = "prod-simulated"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.35"
}

variable "eks_cluster_role_name" {
  description = "Existing IAM role name used by EKS cluster (injected via TF_VAR_eks_cluster_role_name / EKS_CLUSTER_ROLE_NAME variable)"
  type        = string
  default     = ""
}

variable "node_instance_type" {
  description = <<-EOT
    EKS managed node group instance type configured in the node Launch Template.

    Each t3.medium instance supports up to 17 pods under the VPC CNI formula
    (ENIs x (IPs per ENI - 1)) + 2 = 3 x (6 - 1) + 2 = 17 pods, giving 34 pod
    slots across the 2 fixed worker nodes.
  EOT
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 2
}

variable "aws_base_state_bucket" {
  description = "S3 bucket name that stores aws-base Terraform state"
  type        = string
}

variable "aws_base_state_key" {
  description = "S3 object key for infra-base Terraform state"
  type        = string
  default     = "infra/prod-simulated/infra-base/terraform.tfstate"
}

variable "aws_base_state_region" {
  description = "AWS region where aws-base Terraform state bucket is hosted"
  type        = string
  default     = "us-east-1"
}

variable "enable_metrics_server" {
  description = "Install metrics-server in the cluster"
  type        = bool
  default     = true
}

variable "metrics_server_chart_version" {
  description = "Optional metrics-server Helm chart version"
  type        = string
  default     = ""
}
