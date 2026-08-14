terraform {
  required_providers {
    harness = {
      source = "harness/harness"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
    }
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
