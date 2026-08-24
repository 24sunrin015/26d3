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

  # CloudFront는 상태코드별 원시 카운트를 CloudWatch에 안 내려준다(Requests=총량 카운트,
  # 4xxErrorRate/5xxErrorRate=비율%뿐, 2xx/3xx 전용 지표 자체가 없음 — AWS 기본/추가
  # 메트릭 둘 다 확인함). 그래서 총 요청수(정확) + 4xx/5xx(비율×총량 근사) + 나머지를
  # 2xx/3xx 합산(근사)으로 보여준다. 정확한 2xx/3xx 분리가 필요하면 CF 로그를 Athena로
  # 붙여야 하는데, 그건 대시보드 패널이 아니라 별도 쿼리라 이 패널 범위 밖.
  cf_summary_metrics = [
    ["AWS/CloudFront", "Requests", "DistributionId", var.distribution_id, "Region", "Global", { id = "m1", stat = "Sum", label = "총 요청수" }],
    ["AWS/CloudFront", "4xxErrorRate", "DistributionId", var.distribution_id, "Region", "Global", { id = "m2", stat = "Average", visible = false }],
    ["AWS/CloudFront", "5xxErrorRate", "DistributionId", var.distribution_id, "Region", "Global", { id = "m3", stat = "Average", visible = false }],
    [{ expression = "m1*m2/100", label = "4xx (근사)", id = "e1" }],
    [{ expression = "m1*m3/100", label = "5xx (근사)", id = "e2" }],
    [{ expression = "m1-e1-e2", label = "2xx+3xx (근사)", id = "e3" }],
  ]

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 24, height = 3,
        properties = {
          title                = "CloudFront 전체 요청 & 응답코드 분포 (숫자, 근사치 — 정확한 2xx/3xx 분리는 CF 로그/Athena 필요)",
          metrics              = local.cf_summary_metrics,
          view                 = "singleValue",
          region               = "us-east-1",
          period               = 300,
          sparkline            = false,
          setPeriodToTimeRange = true,
        }
      },
      {
        type = "metric", x = 0, y = 3, width = 12, height = 6,
        properties = {
          title       = "EC2 노드 수 (비용 지표 · baseline 2)",
          metrics     = local.node_metrics,
          view        = "timeSeries", stat = "Average", period = 60, region = var.region,
          yAxis       = { left = { min = 0 } },
          annotations = { horizontal = [{ label = "baseline", value = 2 }] }
        }
      },
      {
        type = "metric", x = 12, y = 3, width = 12, height = 6,
        properties = {
          title       = "앱별 응답시간 p99 (SLO: user/product 0.2s, stress 1.0s)",
          metrics     = local.resp_metrics,
          view        = "timeSeries", stat = "p99", period = 60, region = var.region,
          annotations = { horizontal = [{ label = "0.2s", value = 0.2 }, { label = "1.0s", value = 1.0 }] }
        }
      },
      {
        type = "metric", x = 0, y = 9, width = 12, height = 6,
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
        type = "metric", x = 12, y = 9, width = 12, height = 6,
        properties = {
          title   = "정상 호스트 수 (가용성)",
          metrics = local.healthy_metrics,
          view    = "timeSeries", stat = "Average", period = 60, region = var.region
        }
      },
      {
        type = "metric", x = 0, y = 15, width = 8, height = 6,
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
        type = "metric", x = 8, y = 15, width = 8, height = 6,
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
        type = "metric", x = 16, y = 15, width = 8, height = 6,
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
