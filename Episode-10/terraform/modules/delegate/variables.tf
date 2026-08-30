# Harness account ID for delegate registration (from GitHub Variable: HARNESS_ACCOUNT_ID)
variable "account_id" {
  type = string
}

# Token used to authenticate the delegate (from GitHub Secret: HARNESS_DELEGATE_TOKEN)
variable "delegate_token" {
  type      = string
  sensitive = true
}

# Name identifier for the Harness delegate
variable "delegate_name" {
  type    = string
  default = "eks-k8s-delegate"
}

# Number of delegate pod replicas to run
variable "replicas" {
  type    = number
  default = 2
}

# Docker image tag for the delegate version
variable "image_tag" {
  type    = string
  default = "26.07.89707"
}

# EKS cluster where delegate is deployed
variable "eks_cluster_name" {
  type = string
}
