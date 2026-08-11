variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "onlineboutique"
}

variable "db_username" {
  type    = string
  default = "dbadmin"
}

variable "secret_prefix" {
  type    = string
  default = "online-boutique"
}

variable "tags" {
  type    = map(string)
  default = {}
}
