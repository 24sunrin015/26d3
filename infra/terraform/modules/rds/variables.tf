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
