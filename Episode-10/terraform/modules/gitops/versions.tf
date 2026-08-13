terraform {
  required_providers {
    harness = {
      source = "harness/harness"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}
