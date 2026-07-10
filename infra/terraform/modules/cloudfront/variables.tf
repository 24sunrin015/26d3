variable "prefix" { type = string }
variable "alb_dns_name" { type = string }
variable "s3_bucket_id" { type = string }
variable "s3_bucket_arn" { type = string }
variable "s3_bucket_domain_name" { type = string }

# product GET 응답 캐싱 토글. requestid가 매 요청 유니크이므로, 앱 응답이
# requestid를 에코하면 id-키 캐싱은 캐시 히트마다 변조 판정(전 구간 0점) 위험.
# 기본 false(안전) — 당일 바이너리로 "응답에 requestid 미포함" 확인 후 true로 전환.
variable "enable_product_cache" {
  type    = bool
  default = false
}
