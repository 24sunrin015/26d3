# =====================================================================
# RDS 심화 대시보드 — ops의 CPU+커넥션 위젯 하나를 latency/IOPS/처리량/
# 메모리까지 전개. 슬로우쿼리 로그(파라미터그룹 long_query_time=0.1)를
# 로그 위젯으로 바로 노출.
# =====================================================================
locals {
  db_dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title   = "RDS CPU", region = var.region, view = "timeSeries", stat = "Average", period = 60,
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_identifier, { label = "CPU%" }]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title       = "DB 커넥션 (max_connections=200)", region = var.region, view = "timeSeries", stat = "Average", period = 60,
          metrics     = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_identifier, { label = "connections" }]],
          annotations = { horizontal = [{ label = "80% (160)", value = 160, color = "#ff7f0e" }, { label = "max 200", value = 200, color = "#ff0000" }] }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title = "Read/Write Latency", region = var.region, view = "timeSeries", stat = "Average", period = 60,
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.rds_identifier, { label = "read" }],
            [".", "WriteLatency", ".", ".", { label = "write" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title = "Read/Write IOPS", region = var.region, view = "timeSeries", stat = "Average", period = 60,
          metrics = [
            ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", var.rds_identifier, { label = "read iops" }],
            [".", "WriteIOPS", ".", ".", { label = "write iops" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6,
        properties = {
          title = "Read/Write 처리량", region = var.region, view = "timeSeries", stat = "Average", period = 60,
          metrics = [
            ["AWS/RDS", "ReadThroughput", "DBInstanceIdentifier", var.rds_identifier, { label = "read bytes/s" }],
            [".", "WriteThroughput", ".", ".", { label = "write bytes/s" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6,
        properties = {
          title   = "FreeableMemory", region = var.region, view = "timeSeries", stat = "Average", period = 60,
          metrics = [["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", var.rds_identifier, { label = "free mem" }]]
        }
      },
      {
        type = "log", x = 0, y = 18, width = 24, height = 6,
        properties = {
          title  = "최근 슬로우쿼리 (long_query_time=0.1s 초과)",
          region = var.region,
          view   = "table",
          query  = "SOURCE '/aws/rds/instance/${var.rds_identifier}/slowquery' | fields @timestamp, @message | sort @timestamp desc | limit 20"
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "db" {
  dashboard_name = "${var.prefix}-db"
  dashboard_body = local.db_dashboard_body
}
