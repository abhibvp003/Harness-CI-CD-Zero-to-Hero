# Creates ECR repositories to store Docker images for our services
resource "aws_ecr_repository" "repos" {
  for_each = toset(var.repository_names)

  name                 = each.key
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, { Name = each.key })
}

# Lifecycle policy that auto-deletes untagged images after 7 days
resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each   = toset(var.repository_names)
  repository = aws_ecr_repository.repos[each.key].name

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
      action = { type = "expire" }
    }]
  })
}
