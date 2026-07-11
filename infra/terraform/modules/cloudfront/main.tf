locals {
  alb_origin_id = "alb-origin"
  s3_origin_id  = "s3-images-origin"
}

# 관리형 정책 참조
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# /images 프리픽스 제거 (예: /images/product50001.jpg → S3 key product50001.jpg)
# ⚠️ 앱의 S3 키 규칙에 따라 조정 필요 — 제공 바이너리로 검증(TROUBLESHOOTING 참고)
resource "aws_cloudfront_function" "strip_images_prefix" {
  name    = "${var.prefix}-strip-images"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      request.uri = request.uri.replace(/^\/images/, '');
      if (request.uri === '') { request.uri = '/'; }
      return request;
    }
  EOT
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.prefix}-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled     = true
  price_class = "PriceClass_200" # 서울 엣지 포함, 비용 절감
  comment     = "${var.prefix} single endpoint"

  # 오리진 1: ALB (동적 API)
  origin {
    origin_id   = local.alb_origin_id
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # 오리진 2: S3 (정적 이미지, OAC)
  origin {
    origin_id                = local.s3_origin_id
    domain_name              = var.s3_bucket_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # 기본: 동적 API → ALB, 캐시 없음, 전체 메서드 허용
  default_cache_behavior {
    target_origin_id       = local.alb_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # /images/* → S3, 강력 캐싱 (정적 이미지 다운로드)
  ordered_cache_behavior {
    path_pattern           = "/images/*"
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id = data.aws_cloudfront_cache_policy.optimized.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.strip_images_prefix.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # *.cloudfront.net 도메인으로 HTTPS 제공
  }
}

# S3 버킷 정책: 이 배포(OAC)만 GetObject 허용
resource "aws_s3_bucket_policy" "images" {
  bucket = var.s3_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${var.s3_bucket_arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
        }
      }
    }]
  })
}
