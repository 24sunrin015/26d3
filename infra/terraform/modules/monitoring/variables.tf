variable "prefix" { type = string }
variable "region" { type = string }
variable "alb_arn_suffix" { type = string }
variable "target_group_arn_suffixes" {
  type = map(string) # { user=..., product=..., stress=... }
}
variable "rds_identifier" { type = string }
variable "distribution_id" { type = string }
variable "alb_logs_bucket" { type = string }
variable "waf_log_group" { type = string }
variable "node_asg_names" {
  type        = list(string)
  description = "EKS 노드그룹 ASG 이름 (노드 수 = 비용 지표 추적용, ops 대시보드용 통합 리스트)"
}
variable "apps_node_asg_names" {
  type        = list(string)
  description = "apps 노드그룹 ASG 이름 (nodes 대시보드용, stress와 분리)"
}
variable "stress_node_asg_name" {
  type        = string
  description = "stress 노드그룹 ASG 이름 (nodes 대시보드용)"
}
variable "nat_gateway_ids" {
  type        = list(string)
  description = "NAT Gateway ID (처리 바이트 = 숨은 비용 추적용)"
}
variable "codebuild_project_name" {
  type        = string
  description = "이미지 빌드 CodeBuild 프로젝트명 (빌드 성공/실패/소요시간 위젯용)"
}
