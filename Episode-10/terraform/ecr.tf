# ═══════════════════════════════════════════════════════════════════
# ECR Repositories — Created by Terraform (MNC way)
# No aws-cli in pipeline. No access keys needed.
# Terraform creates repos → Pipeline just pushes images (OIDC)
# ═══════════════════════════════════════════════════════════════════

locals {
  ecr_repos = [
    "frontend",
    "cartservice",
    "checkoutservice",
    "productcatalogservice",
    "currencyservice",
    "emailservice",
    "paymentservice",
    "recommendationservice",
    "shippingservice",
    "adservice",
    "loadgenerator",
  ]
}

resource "aws_ecr_repository" "microservices" {
  for_each = toset(local.ecr_repos)

  name                 = each.key
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name      = each.key
    Episode   = "10"
    ManagedBy = "terraform"
  }
}

# Lifecycle policy — delete untagged images after 7 days (cost optimization)
resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each   = toset(local.ecr_repos)
  repository = aws_ecr_repository.microservices[each.key].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Delete untagged images after 7 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 7
      }
      action = {
        type = "expire"
      }
    }]
  })
}
