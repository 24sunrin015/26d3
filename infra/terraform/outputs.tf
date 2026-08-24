# 채점 플랫폼에 제출할 단일 엔드포인트 (프로토콜+주소, 경로 없음)
output "endpoint" {
  description = "제출용 단일 엔드포인트 (CloudFront)"
  value       = "https://${module.cloudfront.distribution_domain_name}"
}

output "cloudfront_domain" {
  value = module.cloudfront.distribution_domain_name
}

# ---- k8s 배포에 필요한 값들 (make k8s가 terraform output으로 읽어 주입) ----
output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "ecr_repository_urls" {
  description = "user/product/stress/hedger ECR URL"
  value       = module.ecr.repository_urls
}

output "codebuild_project_name" {
  description = "make images가 트리거하는 이미지 빌드 CodeBuild 프로젝트"
  value       = module.codebuild.project_name
}

output "codebuild_source_bucket" {
  description = "make images가 provided/ zip을 올리는 버킷 (ALB 로그 버킷 재사용)"
  value       = module.alb.access_logs_bucket
}

output "codebuild_source_key" {
  value = module.codebuild.source_key
}

output "dashboard_urls" {
  description = "CloudWatch 대시보드 콘솔 URL 모음 (ops/svc/db/nodes/security)"
  value       = module.monitoring.dashboard_urls
}

output "rds_address" {
  description = "앱 MYSQL_HOST (엔진명 미포함 주소)"
  value       = module.rds.address
}

output "rds_port" {
  value = module.rds.port
}

output "db_name" {
  value = var.db_name
}

output "db_username" {
  value = var.db_username
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "s3_bucket" {
  value = module.s3.bucket_id
}

output "target_group_arns" {
  description = "user/product/stress 타겟그룹 ARN (TargetGroupBinding용)"
  value       = module.alb.target_group_arns
}

output "stress_node_asg_name" {
  value = module.eks.stress_node_asg_name
}

output "hedger_target_group_arn" {
  description = "hedger 타겟그룹 ARN (TargetGroupBinding용)"
  value       = module.alb.hedger_target_group_arn
}

output "app_s3_role_arn" {
  description = "product SA에 붙일 IRSA 역할 ARN"
  value       = module.irsa_app_s3.iam_role_arn
}
