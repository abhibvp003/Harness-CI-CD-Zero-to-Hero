# Name identifier for the EKS cluster (from GitHub Variable: CLUSTER_NAME)
variable "cluster_name" {
  type = string
}

# Kubernetes version for the EKS cluster
variable "cluster_version" {
  type = string
}

# Subnet IDs where EKS nodes are placed
variable "subnet_ids" {
  type = list(string)
}

# Private subnet IDs for worker node groups (nodes don't need public IPs)
variable "private_subnet_ids" {
  type = list(string)
}

# VPC ID to deploy the EKS cluster into
variable "vpc_id" {
  type = string
}

# VPC CIDR for security group rules
variable "vpc_cidr" {
  type = string
}

# Common tags applied to all EKS resources
variable "tags" {
  type    = map(string)
  default = {}
}

# AWS region for LB Controller and Cluster Autoscaler (from GitHub Variable: AWS_REGION)
variable "region" {
  type = string
}
