# Cluster name for RDS resource tagging
variable "cluster_name" {
  type = string
}

# VPC ID for RDS security group rules
variable "vpc_id" {
  type = string
}

# VPC CIDR for database access rules
variable "vpc_cidr" {
  type = string
}

# Private subnet IDs for the DB subnet group
variable "subnet_ids" {
  type = list(string)
}

# RDS instance size and compute class
variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

# Name of the initial database to create
variable "db_name" {
  type    = string
  default = "onlineboutique"
}

# Master username for RDS authentication
variable "db_username" {
  type    = string
  default = "dbadmin"
}

# Prefix for secrets stored in Secrets Manager
variable "secret_prefix" {
  type    = string
  default = "online-boutique"
}

# Common tags applied to RDS resources
variable "tags" {
  type    = map(string)
  default = {}
}
