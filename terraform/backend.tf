terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    key          = "infra/prod-simulated/infra-k8s/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
