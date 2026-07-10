variable "prefix" { type = string }
variable "repos" {
  type    = list(string)
  default = ["user", "product", "stress"]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repos)

  name                 = "${var.prefix}-${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # 대회 후 clean destroy를 위해

  image_scanning_configuration {
    scan_on_push = false
  }
}

# 오래된 이미지 정리 (레지스트리 비대화 방지)
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "최근 5개 이미지만 유지"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

output "repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
