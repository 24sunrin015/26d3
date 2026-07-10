terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # 로컬 state 전용 (원격 backend·환경 분리 없음 — AGENTS §7)
  backend "local" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

# CloudFront에 붙일 WAF(scope=CLOUDFRONT)는 us-east-1에만 생성 가능.
# 본 설계는 WAF를 ALB(REGIONAL)에 부착하므로 기본은 쓰지 않으나,
# 엣지단 WAF가 필요할 때를 위해 별칭 provider를 준비해 둔다.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}
