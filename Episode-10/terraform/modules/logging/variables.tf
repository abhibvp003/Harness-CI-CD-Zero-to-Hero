variable "domain_name" {
  type = string
}

variable "efk_password" {
  type      = string
  sensitive = true
}

variable "github_username" {
  type = string
}
