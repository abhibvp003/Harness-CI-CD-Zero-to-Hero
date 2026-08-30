# IP range for the VPC network
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

# Name used for EKS cluster and resource tagging (from GitHub Variable: CLUSTER_NAME)
variable "cluster_name" {
  description = "Cluster name for tagging"
  type        = string
}

# AZs for distributing subnets across zones
variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

# Common tags applied to all VPC resources
variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
