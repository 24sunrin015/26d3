# =====================================================================
# 3과제 System Operation — 루트 배선
# 흐름: 사용자 → CloudFront(단일 엔드포인트) → [ALB+WAF → EKS] / [S3 /images]
#       EKS(user/product/stress) → RDS(MySQL Multi-AZ) / S3(이미지 업로드)
# =====================================================================

# ---------------------------------------------------------------------
# 네트워크 (VPC) — 로컬 모듈 (커스터마이즈 용이)
# ---------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  name               = "${local.prefix}-vpc"
  cidr               = var.vpc_cidr
  azs                = local.azs
  public_subnets     = local.public_subnets
  private_subnets    = local.private_subnets
  single_nat_gateway = var.single_nat_gateway
  cluster_name       = local.cluster_name
}

# S3 게이트웨이 엔드포인트 — ECR 이미지 레이어(S3) 및 이미지 버킷 접근을
# NAT 없이 아마존 백본으로 처리(비용·지연 절감, 무료)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = { Name = "${local.prefix}-s3-endpoint" }
}

# ---------------------------------------------------------------------
# EKS — 로컬 모듈 (관리형 노드그룹 t3.medium, 커스터마이즈 용이)
# ---------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  cluster_name           = local.cluster_name
  cluster_version        = var.cluster_version
  region                 = var.region
  endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  node_instance_type = var.node_instance_type
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_desired_size  = var.node_desired_size
}
# 컨트롤러 IRSA + 애드온(helm)은 eks 모듈 내부(modules/eks/addons.tf)에서 관리한다.

# ---------------------------------------------------------------------
# IRSA — product 앱 → S3 이미지 업로드 권한
# ---------------------------------------------------------------------
resource "aws_iam_policy" "app_s3" {
  name        = "${local.prefix}-app-s3"
  description = "product 앱의 이미지 버킷 read/write"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [module.s3.bucket_arn, "${module.s3.bucket_arn}/*"]
      }
    ]
  })
}

module "irsa_app_s3" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name = "${local.prefix}-app-s3"

  role_policy_arns = {
    s3 = aws_iam_policy.app_s3.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:product-sa"]
    }
  }
}

# ---------------------------------------------------------------------
# 데이터/스토리지/레지스트리 (로컬 모듈)
# ---------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  prefix = local.prefix
  repos  = ["user", "product", "stress"]
}

module "rds" {
  source = "./modules/rds"

  prefix            = local.prefix
  identifier        = "${local.prefix}-rds-instance" # 과제지 고정 이름
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnets
  instance_class    = var.db_instance_class
  engine_version    = var.db_engine_version
  db_name           = var.db_name
  username          = var.db_username
  password          = random_password.db.result
  allocated_storage = var.db_allocated_storage
  ingress_sg_ids    = [module.eks.node_security_group_id]

  # 테이블 자동 적용(in-cluster 파드)용 — 노드 준비 후 실행되도록 node_asgs 전달
  cluster_name = module.eks.cluster_name
  region       = var.region
  node_asgs    = module.eks.node_asg_names
}

resource "random_password" "db" {
  length  = 20
  special = false # MySQL 접속 문자열/URL 인코딩 이슈 회피
}

module "s3" {
  source = "./modules/s3"

  prefix     = local.prefix
  student_id = var.student_id
}

# ---------------------------------------------------------------------
# 엣지/트래픽 (ALB → WAF, CloudFront)
# ---------------------------------------------------------------------
module "alb" {
  source = "./modules/alb"

  prefix         = local.prefix
  vpc_id         = module.vpc.vpc_id
  public_subnets = module.vpc.public_subnets
  # ALB → 노드(8080)로의 트래픽 허용을 위해 노드 SG 참조
  node_sg_id = module.eks.node_security_group_id
}

module "waf" {
  source = "./modules/waf"

  prefix  = local.prefix
  alb_arn = module.alb.alb_arn
}

module "cloudfront" {
  source = "./modules/cloudfront"

  prefix                = local.prefix
  alb_dns_name          = module.alb.alb_dns_name
  s3_bucket_id          = module.s3.bucket_id
  s3_bucket_arn         = module.s3.bucket_arn
  s3_bucket_domain_name = module.s3.bucket_regional_domain_name
}

# ---------------------------------------------------------------------
# 관측성 (CloudWatch 대시보드/알람 + Athena 로그 분석)
# ---------------------------------------------------------------------
module "monitoring" {
  source = "./modules/monitoring"

  prefix                    = local.prefix
  region                    = var.region
  cluster_name              = local.cluster_name
  alb_arn_suffix            = module.alb.alb_arn_suffix
  target_group_arn_suffixes = module.alb.target_group_arn_suffixes
  rds_identifier            = module.rds.identifier
  distribution_id           = module.cloudfront.distribution_id
  alb_logs_bucket           = module.alb.access_logs_bucket
  waf_log_group             = module.waf.log_group_name
  node_asg_names            = module.eks.node_asg_names
}
