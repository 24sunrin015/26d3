variable "prefix" { type = string }
variable "region" { type = string }

variable "source_bucket_name" {
  type        = string
  description = "빌드 소스(zip) 업로드 대상 버킷 (ALB 로그 버킷 재사용, build-src/ 프리픽스)"
}

variable "source_key" {
  type    = string
  default = "build-src/source.zip"
}
