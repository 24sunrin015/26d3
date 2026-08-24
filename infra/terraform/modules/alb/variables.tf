variable "prefix" { type = string }
variable "vpc_id" { type = string }
variable "public_subnets" { type = list(string) }
variable "node_sg_id" { type = string }
variable "additional_apps" { type = list(string) }
variable "enable_hedger" { type = bool }
