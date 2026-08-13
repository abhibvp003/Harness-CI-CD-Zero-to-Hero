# List of container repository names to create
variable "repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
}

# Common tags applied to ECR repositories
variable "tags" {
  type    = map(string)
  default = {}
}
