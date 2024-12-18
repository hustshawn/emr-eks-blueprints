terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.47"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.4"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.3"
    }
  }

  ##  Used for end-to-end testing on project; update to suit your needs
  backend "s3" {
    bucket  = "tf-eks-remote-states"
    region  = "ap-southeast-1"
    key     = "e2e/emr-eks-karpenter/terraform.tfstate"
    profile = "account-a"
  }
}
