data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  prefix = var.name_prefix

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /16을 /20 서브넷으로 분할: 앞쪽은 public, 뒤쪽은 private
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  cluster_name = "${local.prefix}-eks"

  common_tags = {
    Project   = "wsk2026-day3"
    Task      = "system-operation"
    ManagedBy = "terraform"
    StudentId = var.student_id
    # EKS/CloudMap 등이 요구하는 클러스터 소유권 태그는 각 모듈에서 부여
  }
}
