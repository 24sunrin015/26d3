locals {
  tg_keys = keys(var.target_group_arn_suffixes)

  # 노드 수 (비용 지표) — ASG GroupInServiceInstances
  node_metrics = [
    for asg in var.node_asg_names :
    ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", asg]
  ]

  # 앱별 응답시간 (p99) — TargetResponseTime
  resp_metrics = [
    for k in local.tg_keys :
    ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", var.target_group_arn_suffixes[k], "LoadBalancer", var.alb_arn_suffix, { label = k }]
  ]

  # 앱별 정상 호스트 수
  healthy_metrics = [
    for k in local.tg_keys :
    ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_arn_suffixes[k], "LoadBalancer", var.alb_arn_suffix, { label = k }]
  ]

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title       = "EC2 노드 수 (비용 지표 · baseline 2)",
          metrics     = local.node_metrics,
          view        = "timeSeries", stat = "Average", period = 60, region = var.region,
          yAxis       = { left = { min = 0 } },
          annotations = { horizontal = [{ label = "baseline", value = 2 }] }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title       = "앱별 응답시간 p99 (SLO: user/product 0.2s, stress 1.0s)",
          metrics     = local.resp_metrics,
          view        = "timeSeries", stat = "p99", period = 60, region = var.region,
          annotations = { horizontal = [{ label = "0.2s", value = 0.2 }, { label = "1.0s", value = 1.0 }] }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title = "ALB 상태코드",
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "2xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "4xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "target 5xx" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "elb 5xx" }]
          ],
          view = "timeSeries", stat = "Sum", period = 60, region = var.region
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title   = "정상 호스트 수 (가용성)",
          metrics = local.healthy_metrics,
          view    = "timeSeries", stat = "Average", period = 60, region = var.region
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 8, height = 6,
        properties = {
          title = "RDS",
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_identifier, { label = "CPU%" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_identifier, { label = "connections", yAxis = "right" }]
          ],
          view = "timeSeries", stat = "Average", period = 60, region = var.region
        }
      },
      {
        type = "metric", x = 8, y = 12, width = 8, height = 6,
        properties = {
          title = "CloudFront (캐시 효율)",
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", var.distribution_id, "Region", "Global", { label = "requests" }],
            ["AWS/CloudFront", "CacheHitRate", "DistributionId", var.distribution_id, "Region", "Global", { label = "hit rate", yAxis = "right" }]
          ],
          view = "timeSeries", stat = "Average", period = 60, region = "us-east-1"
        }
      },
      {
        type = "metric", x = 16, y = 12, width = 8, height = 6,
        properties = {
          title = "WAF 차단 (전체)",
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", "${var.prefix}-waf-web-acl", "Region", var.region, "Rule", "ALL", { label = "blocked" }],
            ["AWS/WAFV2", "AllowedRequests", "WebACL", "${var.prefix}-waf-web-acl", "Region", var.region, "Rule", "ALL", { label = "allowed", yAxis = "right" }]
          ],
          view = "timeSeries", stat = "Sum", period = 60, region = var.region
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.prefix}-ops"
  dashboard_body = local.dashboard_body
}
