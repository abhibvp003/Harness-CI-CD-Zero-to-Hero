variable "account_id" {
  type = string
}

variable "delegate_token" {
  type      = string
  sensitive = true
}

variable "delegate_name" {
  type    = string
  default = "eks-k8s-delegate"
}

variable "replicas" {
  type    = number
  default = 2
}

variable "image_tag" {
  type    = string
  default = "26.07.89707"
}

variable "eks_cluster_name" {
  type = string
}
