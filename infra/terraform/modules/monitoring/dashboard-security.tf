# =====================================================================
# WAF/CDN 심화 대시보드 — ops의 "WAF 차단(전체)" 위젯을 룰별로 분해하고
# CloudFront 지표를 추가. 룰 이름은 modules/waf/main.tf의 metric_name과
# 동기화해야 한다(룰 추가/삭제 시 여기도 갱신).
# =====================================================================
locals {
  security_waf_web_acl = "${var.prefix}-waf-web-acl"
  security_waf_rules = [
    "CommonRuleSet", "KnownBadInputs", "SQLi", "IpReputation",
    "MethodWhitelist", "UserEmailValidation", "BlockedUserAgents",
  ]
  security_waf_blocked_metrics = [
    for r in local.security_waf_rules :
    ["AWS/WAFV2", "BlockedRequests", "WebACL", local.security_waf_web_acl, "Region", var.region, "Rule", r, { label = r }]
  ]

  dashboard_security_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 24, height = 6,
        properties = {
          title = "WAF 룰별 차단 (룰 목록: modules/waf/main.tf와 동기화)", metrics = local.security_waf_blocked_metrics,
          view  = "timeSeries", stat = "Sum", period = 60, region = var.region
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title = "CloudFront 요청/캐시 히트율", region = "us-east-1", view = "timeSeries", stat = "Average", period = 60,
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", var.distribution_id, "Region", "Global", { label = "requests", stat = "Sum" }],
            [".", "CacheHitRate", ".", ".", ".", ".", { label = "hit rate %", yAxis = "right" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title = "CloudFront 오류율", region = "us-east-1", view = "timeSeries", stat = "Average", period = 60,
          metrics = [
            ["AWS/CloudFront", "4xxErrorRate", "DistributionId", var.distribution_id, "Region", "Global", { label = "4xx %" }],
            [".", "5xxErrorRate", ".", ".", ".", ".", { label = "5xx %" }],
            [".", "TotalErrorRate", ".", ".", ".", ".", { label = "total %" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6,
        properties = {
          title   = "CloudFront Origin Latency", region = "us-east-1", view = "timeSeries", stat = "Average", period = 60,
          metrics = [["AWS/CloudFront", "OriginLatency", "DistributionId", var.distribution_id, "Region", "Global", { label = "origin latency ms" }]]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6,
        properties = {
          title = "CloudFront vs ALB 요청수 (캐시 오프로드 확인)", view = "timeSeries", period = 60, stat = "Sum", region = var.region,
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", var.distribution_id, "Region", "Global", { label = "CF requests", region = "us-east-1" }],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { label = "ALB requests(origin 도달)", region = var.region }],
          ]
        }
      },
      {
        type = "log", x = 0, y = 18, width = 24, height = 6,
        properties = {
          title  = "차단 상위 룰 (waf-blocked-user-agents 저장쿼리와 동일)",
          region = var.region,
          view   = "table",
          query  = "SOURCE '${var.waf_log_group}' | fields @timestamp, httpRequest.clientIp, httpRequest.uri, terminatingRuleId | filter action = \"BLOCK\" | stats count(*) as hits by terminatingRuleId | sort hits desc"
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "security" {
  dashboard_name = "${var.prefix}-security"
  dashboard_body = local.dashboard_security_body
}
