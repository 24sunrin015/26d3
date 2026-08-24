output "alb_arn" {
  value = aws_lb.this.arn
}
output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}
output "alb_dns_name" {
  value = aws_lb.this.dns_name
}
output "target_group_arns" {
  value = { for k, tg in aws_lb_target_group.app : k => tg.arn }
}
output "target_group_arn_suffixes" {
  value = { for k, tg in aws_lb_target_group.app : k => tg.arn_suffix }
}

output "hedger_target_group_arn" {
  value = aws_lb_target_group.hedger.arn
}
output "access_logs_bucket" {
  value = aws_s3_bucket.logs.id
}
