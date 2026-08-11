variable "aws_region" {
  type = string
}

variable "secret_name" {
  type    = string
  default = "online-boutique/app-secrets"
}

variable "tags" {
  type    = map(string)
  default = {}
}
