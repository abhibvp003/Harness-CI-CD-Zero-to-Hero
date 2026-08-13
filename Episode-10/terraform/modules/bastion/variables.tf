variable "cluster_name" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t2.medium"
}

variable "subnet_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
