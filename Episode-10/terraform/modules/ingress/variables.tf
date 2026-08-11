variable "cluster_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "node_role_name" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
