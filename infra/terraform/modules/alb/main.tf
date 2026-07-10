variable "prefix" { type = string }
variable "vpc_id" { type = string }
variable "public_subnets" { type = list(string) }
variable "node_sg_id" { type = string }

locals {
  apps = ["user", "product", "stress"]
}

# CloudFront 오리진 전용으로만 ALB 노출 (직접 IP 접근 차단)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "${var.prefix}-alb-sg"
  description = "ALB - allow 80 from CloudFront origin-facing only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from CloudFront edge"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB → 워커노드(8080) 허용
resource "aws_security_group_rule" "node_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = var.node_sg_id
  source_security_group_id = aws_security_group.alb.id
  description              = "ALB to app pods (8080)"
}

resource "aws_lb" "this" {
  name               = "${var.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnets

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "alb-access-logs"
    enabled = true
  }
}

# 앱별 타겟그룹 (IP 모드 — EKS 파드가 TargetGroupBinding으로 등록)
resource "aws_lb_target_group" "app" {
  for_each = toset(local.apps)

  name        = "${var.prefix}-${each.key}-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/healthcheck"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 3
    interval            = 10
    matcher             = "200"
  }

  # 파드 롤링 시 빠른 드레이닝 (비용·배포속도)
  deregistration_delay = 15
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # 미매칭(미제공 경로) → 404 (과제지 §7: 제공하지 않는 경로는 404)
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"not found\"}"
      status_code  = "404"
    }
  }
}

# 경로 라우팅: /v1/<app> → 해당 TG
resource "aws_lb_listener_rule" "app" {
  for_each = { for i, a in local.apps : a => i }

  listener_arn = aws_lb_listener.http.arn
  priority     = 10 + each.value

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }

  condition {
    path_pattern {
      values = ["/v1/${each.key}", "/v1/${each.key}/*"]
    }
  }
}

# /healthcheck → user TG로 포워딩 (엣지/외부 헬스체크 응답)
resource "aws_lb_listener_rule" "healthcheck" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["user"].arn
  }

  condition {
    path_pattern {
      values = ["/healthcheck"]
    }
  }
}

# ---- ALB 접근 로그 버킷 (Athena 분석 원천) ----
resource "aws_s3_bucket" "logs" {
  bucket        = "${var.prefix}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.main.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/alb-access-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/alb-access-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

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
output "access_logs_bucket" {
  value = aws_s3_bucket.logs.id
}
