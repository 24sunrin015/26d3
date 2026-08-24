# 연수메모 핵심: "500 에러 0 원칙" — ALB 5xx 발생 즉시 경보
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.prefix}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  period              = 60
  statistic           = "Sum"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  treat_missing_data  = "notBreaching"
  alarm_description   = "앱 5xx 발생 (500 에러 0 원칙)"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "${var.prefix}-elb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  period              = 60
  statistic           = "Sum"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  treat_missing_data  = "notBreaching"
  alarm_description   = "ELB 레벨 5xx (백엔드 불가/타임아웃)"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# 앱별 정상 호스트 0 (가용성 붕괴)
resource "aws_cloudwatch_metric_alarm" "unhealthy" {
  for_each = var.target_group_arn_suffixes

  alarm_name          = "${var.prefix}-${each.key}-no-healthy-host"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  threshold           = 1
  period              = 60
  statistic           = "Average"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  treat_missing_data  = "breaching"
  alarm_description   = "${each.key} 정상 파드 없음"

  dimensions = {
    TargetGroup  = each.value
    LoadBalancer = var.alb_arn_suffix
  }
}

# 앱별 응답시간 p99 SLO 초과
resource "aws_cloudwatch_metric_alarm" "latency" {
  for_each = var.target_group_arn_suffixes

  alarm_name          = "${var.prefix}-${each.key}-latency-slo"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = each.key == "stress" ? 1.0 : 0.2
  period              = 60
  extended_statistic  = "p99"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  treat_missing_data  = "notBreaching"
  alarm_description   = "${each.key} p99 응답시간이 SLO 초과"

  dimensions = {
    TargetGroup  = each.value
    LoadBalancer = var.alb_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.prefix}-rds-connections-80pct"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 160 # max_connections=200의 80%
  period              = 60
  statistic           = "Average"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  treat_missing_data  = "notBreaching"
  alarm_description   = "DB 커넥션이 max_connections(200)의 80%를 초과 (풀 고갈 위험)"

  dimensions = {
    DBInstanceIdentifier = var.rds_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 80
  period              = 60
  statistic           = "Average"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  treat_missing_data  = "notBreaching"
  alarm_description   = "RDS CPU 80% 초과 (병목)"

  dimensions = {
    DBInstanceIdentifier = var.rds_identifier
  }
}

# ---- WAF 로그 실시간 분석 (CloudWatch Logs Insights 저장 쿼리) ----
# 당일 악성 패턴 역산 → WAF 룰 즉시 보정에 사용
resource "aws_cloudwatch_query_definition" "waf_blocked_ua" {
  name            = "${var.prefix}/waf-blocked-user-agents"
  log_group_names = [var.waf_log_group]

  query_string = <<-EOQ
    fields @timestamp, httpRequest.clientIp, httpRequest.uri, terminatingRuleId, httpRequest.headers.0.value
    | filter action = "BLOCK"
    | stats count(*) as hits by terminatingRuleId
    | sort hits desc
  EOQ
}

resource "aws_cloudwatch_query_definition" "waf_ua_dist" {
  name            = "${var.prefix}/waf-user-agent-distribution"
  log_group_names = [var.waf_log_group]

  query_string = <<-EOQ
    fields @timestamp, action, httpRequest.uri
    | parse @message /"name":"[Uu]ser-[Aa]gent","value":"(?<ua>[^"]*)"/
    | stats count(*) as hits by ua, action
    | sort hits desc
    | limit 50
  EOQ
}

resource "aws_cloudwatch_query_definition" "waf_blocked_detail" {
  name            = "${var.prefix}/waf-blocked-detail"
  log_group_names = [var.waf_log_group]

  query_string = <<-EOQ
    fields @timestamp, httpRequest.clientIp, httpRequest.country, httpRequest.httpMethod, httpRequest.uri, terminatingRuleId
    | filter action = "BLOCK"
    | sort @timestamp desc
    | limit 200
  EOQ
}
