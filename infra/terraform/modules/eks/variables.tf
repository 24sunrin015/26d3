variable "cluster_name" { type = string }
variable "cluster_version" { type = string }
variable "region" {
  type        = string
  description = "애드온(helm)용 리전"
}
variable "vpc_id" { type = string }
variable "subnet_ids" {
  type        = list(string)
  description = "컨트롤플레인 ENI·노드가 위치할 프라이빗 서브넷"
}
variable "endpoint_public_access" {
  type    = bool
  default = true
}
variable "enable_app_log_shipping" {
  type        = bool
  default     = false
  description = "앱 컨테이너 로그를 CloudWatch로 보내는 경량 Fluent Bit(옵션). 기본 false — 관측은 metrics-server + agentless 로그로 충분(operation-strategy §6)."
}
variable "node_instance_type" { type = string }
variable "apps_node_count" {
  type        = number
  default     = 1
  description = "apps(user/product) 노드그룹 고정 대수. sleep이라 CPU 0 → 1대 충분."
}
variable "stress_node_max" {
  type        = number
  default     = 2
  description = "stress 노드그룹 최대 대수(min/desired=1 고정, CA가 최대 여기까지 스케일)."
}
variable "tags" {
  type    = map(string)
  default = {}
}
