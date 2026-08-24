# =====================================================================
# 서비스 심화 대시보드 — ops의 앱별 p99 위젯 하나를 앱별/percentile별로
# 전개. target_group_arn_suffixes map을 그대로 순회해 앱이 늘어도 자동 반영.
# =====================================================================
locals {
  svc_tg_keys  = keys(var.target_group_arn_suffixes)
  svc_tg_count = length(local.svc_tg_keys)
  svc_col_w    = floor(24 / max(local.svc_tg_count, 1))
  svc_slo = {
    for k in local.svc_tg_keys : k => (k == "stress" ? 1.0 : 0.2)
  }

  # 앱별 평균 응답시간 — 앱마다 독립 위젯(SLO/critical 라인 포함)
  svc_avg_widgets = [
    for i, k in local.svc_tg_keys : {
      type = "metric", x = i * local.svc_col_w, y = 0, width = local.svc_col_w, height = 6,
      properties = {
        title = "${k} 평균 응답시간 (SLO ${local.svc_slo[k]}s)",
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", var.target_group_arn_suffixes[k], "LoadBalancer", var.alb_arn_suffix, { label = k }]
        ],
        view  = "timeSeries", stat = "Average", period = 60, region = var.region,
        yAxis = { left = { min = 0, max = 2 } },
        annotations = {
          horizontal = [
            { label = "SLO ${local.svc_slo[k]}s", value = local.svc_slo[k], color = "#ff7f0e" },
            { label = "Critical 5s", value = 5.0, color = "#ff0000" },
          ]
        }
      }
    }
  ]

  svc_p90_metrics = [for k in local.svc_tg_keys : ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", var.target_group_arn_suffixes[k], "LoadBalancer", var.alb_arn_suffix, { stat = "p90", label = "${k} p90" }]]
  svc_p95_metrics = [for k in local.svc_tg_keys : ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", var.target_group_arn_suffixes[k], "LoadBalancer", var.alb_arn_suffix, { stat = "p95", label = "${k} p95" }]]
  svc_p99_metrics = [for k in local.svc_tg_keys : ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", var.target_group_arn_suffixes[k], "LoadBalancer", var.alb_arn_suffix, { stat = "p99", label = "${k} p99" }]]

  svc_4xx_metrics    = [for k in local.svc_tg_keys : ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "TargetGroup", var.target_group_arn_suffixes[k], "LoadBalancer", var.alb_arn_suffix, { label = "${k} 4xx" }]]
  svc_5xx_metrics    = [for k in local.svc_tg_keys : ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "TargetGroup", var.target_group_arn_suffixes[k], "LoadBalancer", var.alb_arn_suffix, { label = "${k} 5xx" }]]
  svc_healthy_metric = [for k in local.svc_tg_keys : ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_arn_suffixes[k], "LoadBalancer", var.alb_arn_suffix, { label = "${k} healthy" }]]
  svc_unhealthy_metr = [for k in local.svc_tg_keys : ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", var.target_group_arn_suffixes[k], "LoadBalancer", var.alb_arn_suffix, { label = "${k} unhealthy" }]]

  svc_dashboard_body = jsonencode({
    widgets = concat(local.svc_avg_widgets, [
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title       = "p90 응답시간 (앱별)", metrics = local.svc_p90_metrics,
          view        = "timeSeries", period = 60, region = var.region, yAxis = { left = { min = 0 } },
          annotations = { horizontal = [{ label = "SLO 0.2s", value = 0.2, color = "#ff7f0e" }, { label = "SLO 1.0s", value = 1.0, color = "#d62728" }] }
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title       = "p95 응답시간 (앱별)", metrics = local.svc_p95_metrics,
          view        = "timeSeries", period = 60, region = var.region, yAxis = { left = { min = 0 } },
          annotations = { horizontal = [{ label = "SLO 0.2s", value = 0.2, color = "#ff7f0e" }, { label = "SLO 1.0s", value = 1.0, color = "#d62728" }] }
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6,
        properties = {
          title       = "p99 응답시간 (앱별)", metrics = local.svc_p99_metrics,
          view        = "timeSeries", period = 60, region = var.region, yAxis = { left = { min = 0 } },
          annotations = { horizontal = [{ label = "SLO 0.2s", value = 0.2, color = "#ff7f0e" }, { label = "SLO 1.0s", value = 1.0, color = "#d62728" }, { label = "Critical 5s", value = 5.0, color = "#ff0000" }] }
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6,
        properties = {
          title = "전체 요청수 & 5xx", region = var.region, view = "timeSeries", stat = "Sum", period = 60,
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { label = "requests" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { label = "target 5xx" }],
          ]
        }
      },
      {
        type       = "metric", x = 0, y = 18, width = 12, height = 6,
        properties = { title = "앱별 4xx", metrics = local.svc_4xx_metrics, view = "timeSeries", stat = "Sum", period = 60, region = var.region }
      },
      {
        type       = "metric", x = 12, y = 18, width = 12, height = 6,
        properties = { title = "앱별 5xx", metrics = local.svc_5xx_metrics, view = "timeSeries", stat = "Sum", period = 60, region = var.region }
      },
      {
        type       = "metric", x = 0, y = 24, width = 12, height = 6,
        properties = { title = "정상 호스트 수 (앱별)", metrics = local.svc_healthy_metric, view = "timeSeries", stat = "Average", period = 60, region = var.region }
      },
      {
        type       = "metric", x = 12, y = 24, width = 12, height = 6,
        properties = { title = "비정상 호스트 수 (앱별)", metrics = local.svc_unhealthy_metr, view = "timeSeries", stat = "Average", period = 60, region = var.region }
      },
      {
        type = "metric", x = 0, y = 30, width = 12, height = 6,
        properties = {
          title = "ALB 커넥션", region = var.region, view = "timeSeries", period = 60,
          metrics = [
            ["AWS/ApplicationELB", "ActiveConnectionCount", "LoadBalancer", var.alb_arn_suffix, { label = "active", stat = "Average" }],
            [".", "NewConnectionCount", ".", ".", { label = "new (sum)", stat = "Sum" }],
          ]
        }
      },
    ])
  })
}

resource "aws_cloudwatch_dashboard" "svc" {
  dashboard_name = "${var.prefix}-svc"
  dashboard_body = local.svc_dashboard_body
}
