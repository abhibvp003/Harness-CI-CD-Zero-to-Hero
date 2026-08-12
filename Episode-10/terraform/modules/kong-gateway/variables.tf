variable "domain_name" {
  description = "Domain name for Kong Ingress routes and ACM certificate lookup"
  type        = string
}

variable "kong_admin_password" {
  description = "Kong Manager UI password (from GitHub Secrets)"
  type        = string
  sensitive   = true
}
