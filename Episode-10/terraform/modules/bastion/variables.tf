# Cluster name for bastion resource tagging (from GitHub Variable: CLUSTER_NAME)
variable "cluster_name" {
  type = string
}

# EC2 instance type for the bastion host
variable "instance_type" {
  type    = string
  default = "t2.medium"
}

# Subnet where the bastion host is launched
variable "subnet_id" {
  type = string
}

# VPC ID for bastion security group rules
variable "vpc_id" {
  type = string
}

# EKS cluster name for kubectl access setup
variable "eks_cluster_name" {
  type = string
}

# Common tags applied to bastion resources
variable "tags" {
  type    = map(string)
  default = {}
}

# AWS region for bastion host deployment (from GitHub Variable: AWS_REGION)
variable "aws_region" {
  description = "AWS region"
  type        = string
}
