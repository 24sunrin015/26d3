# =====================================================================
# 이미지 빌드용 CodeBuild — 로컬 Docker 없이 이미지 빌드/ECR 푸시.
# 현장 로컬 환경(Docker 사용 곤란)에 맞춰 provided/ 바이너리를 zip으로
# S3에 올리면 CodeBuild가 docker/Dockerfile로 빌드해 ECR에 푸시한다.
# 빌드 대상은 하드코딩하지 않고 zip 안 provided/* 를 순회 → 새 바이너리
# 추가 시 ECR repo만 만들면(ecr 모듈 repos에 이름 추가) 스크립트/buildspec
# 수정 없이 그대로 대응된다.
# =====================================================================

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.prefix}-image-build"
  retention_in_days = 7
}

resource "aws_iam_role" "codebuild" {
  name = "${var.prefix}-codebuild-image-build"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.prefix}-codebuild-image-build"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
        ]
        # 접두사 고정 패턴(${prefix}-*)이라 새 repo 추가 시 정책 수정 불필요
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.prefix}-*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.source_bucket_name}/${var.source_key}"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.codebuild.arn}:*"
      },
    ]
  })
}

resource "aws_codebuild_project" "image_build" {
  name          = "${var.prefix}-image-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # docker build/push는 CodeBuild 컨테이너 내 dockerd 필요

    environment_variable {
      name  = "ECR_REGISTRY"
      value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
    }

    environment_variable {
      name  = "APP_NAMES"
      value = join(" ", concat(["user", "product", "stress"], var.additional_apps))
    }
  }

  source {
    type      = "S3"
    location  = "${var.source_bucket_name}/${var.source_key}"
    buildspec = <<-YAML
      version: 0.2
      phases:
        pre_build:
          commands:
            - echo "==> ECR login"
            - aws ecr get-login-password --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
        build:
          commands:
            - |
              for app in $APP_NAMES; do
                test -f "provided/$app"
                repo="$ECR_REGISTRY/${var.prefix}-$app"
                echo "==> build & push: $app -> $repo:latest"
                docker build --platform linux/amd64 -f docker/Dockerfile --build-arg APP="$app" -t "$repo:latest" .
                docker push "$repo:latest"
              done
            - docker build --platform linux/amd64 -t "$ECR_REGISTRY/${var.prefix}-hedger:latest" apps/hedger
            - docker push "$ECR_REGISTRY/${var.prefix}-hedger:latest"
    YAML
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }
}
