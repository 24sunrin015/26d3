variable "prefix" { type = string }
variable "identifier" { type = string } # 과제지 고정: apdev-rds-instance
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) } # private, ≥2 AZ (Multi-AZ)
variable "instance_class" { type = string }
variable "engine_version" { type = string }
variable "db_name" { type = string }
variable "username" { type = string }
variable "password" {
  type      = string
  sensitive = true
}
variable "allocated_storage" { type = number }
variable "ingress_sg_ids" {
  type        = list(string)
  description = "3306 접근 허용할 보안그룹(EKS 노드)"
}

# 테이블 자동 적용(null_resource)이 in-cluster mysql 파드로 private RDS에 접근하기 위해 필요
variable "cluster_name" {
  type        = string
  description = "테이블 적용용 kubectl 대상 클러스터"
}
variable "region" { type = string }
variable "node_asgs" {
  type        = list(string)
  description = "노드그룹 ASG 이름(노드 준비 후에만 known) — 테이블 적용을 노드 뒤로 순서화"
}
