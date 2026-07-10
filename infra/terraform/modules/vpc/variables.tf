variable "name" { type = string }
variable "cidr" { type = string }
variable "azs" { type = list(string) }
variable "public_subnets" { type = list(string) }
variable "private_subnets" { type = list(string) }
variable "single_nat_gateway" {
  type    = bool
  default = true
}
variable "cluster_name" {
  type        = string
  description = "EKS 서브넷 탐색 태그(kubernetes.io/cluster/<name>)용"
}
variable "tags" {
  type    = map(string)
  default = {}
}
