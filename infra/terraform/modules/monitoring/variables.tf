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
  description = "EKS 노드그룹 ASG 이름 (노드 수 = 비용 지표 추적용)"
}
