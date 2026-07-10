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
variable "enable_container_insights" {
  type        = bool
  default     = true
  description = "Container Insights(amazon-cloudwatch-observability): 파드 실시간 메트릭+로그. false면 로그는 standalone Fluent Bit로 폴백."
}
variable "node_instance_type" { type = string }
variable "node_min_size" { type = number }
variable "node_max_size" { type = number }
variable "node_desired_size" { type = number }
variable "tags" {
  type    = map(string)
  default = {}
}
