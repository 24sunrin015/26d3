variable "prefix" { type = string }
variable "repos" {
  type    = list(string)
  default = ["user", "product", "stress"]
}
