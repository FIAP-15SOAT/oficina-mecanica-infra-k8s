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

variable "eks_node_role_name" {
  description = "Existing IAM role name used by EKS managed node group (injected via TF_VAR_eks_node_role_name / EKS_NODE_ROLE_NAME variable)"
  type        = string
  default     = ""
}

variable "node_instance_type" {
  description = <<-EOT
    EKS managed node group instance type.

    O limite que decide este valor nao e CPU nem memoria: e o teto de pods por
    node do VPC CNI, dado por (ENIs x (IPs por ENI - 1)) + 2.

      t3.small  -> 3 x (4 - 1) + 2 = 11 pods
      t3.medium -> 3 x (6 - 1) + 2 = 17 pods

    Com 11 pods o cluster ja nao comporta o `maxReplicas: 5` do HPA da API
    junto dos workloads de sistema, e nao comporta de forma alguma o DaemonSet
    do agente de observabilidade. Ver o PR que acompanha esta mudanca.
  EOT
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 1
}

variable "aws_base_state_bucket" {
  description = "S3 bucket name that stores aws-base Terraform state"
  type        = string
  default     = "bkt-oficina-mecanica"
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

variable "k8s_namespace" {
  description = "Kubernetes namespace for shared workloads"
  type        = string
  default     = "oficina"
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

variable "api_node_port" {
  description = "NodePort on which the API is reached directly through the cluster nodes"
  type        = number
  default     = 30080
}
