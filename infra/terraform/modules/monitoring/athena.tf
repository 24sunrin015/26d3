data "aws_caller_identity" "current" {}

# ---- Athena 결과 버킷 & 워크그룹 ----
resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.prefix}-athena-results-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_athena_workgroup" "main" {
  name          = "${var.prefix}-wg"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/query-results/"
    }
  }
}

resource "aws_glue_catalog_database" "logs" {
  name = "${replace(var.prefix, "-", "_")}_logs"
}

# ---- ALB Access Log 외부 테이블 (RegexSerDe) ----
locals {
  # ALB access log 표준 포맷 (2025 docs/Athena.md 검증본)
  alb_log_regex = trimspace(<<-EOT
    ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*):([0-9]*) ([^ ]*)[:-]([0-9]*) ([-.0-9]*) ([-.0-9]*) ([-.0-9]*) (|[-0-9]*) (-|[-0-9]*) ([-0-9]*) ([-0-9]*) "([^ ]*) (.*) (- |[^ ]*)" "([^"]*)" ([A-Z0-9-_]+) ([A-Za-z0-9.-]*) ([^ ]*) "([^"]*)" "([^"]*)" "([^"]*)" ([-.0-9]*) ([^ ]*) "([^"]*)" "([^"]*)" "([^ ]*)" "([^\s]+?)" "([^\s]+)" "([^ ]*)" "([^ ]*)" ?([^ ]*)?
  EOT
  )

  alb_log_columns = [
    { name = "type", type = "string" },
    { name = "time", type = "string" },
    { name = "elb", type = "string" },
    { name = "client_ip", type = "string" },
    { name = "client_port", type = "int" },
    { name = "target_ip", type = "string" },
    { name = "target_port", type = "int" },
    { name = "request_processing_time", type = "double" },
    { name = "target_processing_time", type = "double" },
    { name = "response_processing_time", type = "double" },
    { name = "elb_status_code", type = "int" },
    { name = "target_status_code", type = "string" },
    { name = "received_bytes", type = "bigint" },
    { name = "sent_bytes", type = "bigint" },
    { name = "request_verb", type = "string" },
    { name = "request_url", type = "string" },
    { name = "request_proto", type = "string" },
    { name = "user_agent", type = "string" },
    { name = "ssl_cipher", type = "string" },
    { name = "ssl_protocol", type = "string" },
    { name = "target_group_arn", type = "string" },
    { name = "trace_id", type = "string" },
    { name = "domain_name", type = "string" },
    { name = "chosen_cert_arn", type = "string" },
    { name = "matched_rule_priority", type = "string" },
    { name = "request_creation_time", type = "string" },
    { name = "actions_executed", type = "string" },
    { name = "redirect_url", type = "string" },
    { name = "lambda_error_reason", type = "string" },
    { name = "target_port_list", type = "string" },
    { name = "target_status_code_list", type = "string" },
    { name = "classification", type = "string" },
    { name = "classification_reason", type = "string" },
    { name = "conn_trace_id", type = "string" },
  ]
}

resource "aws_glue_catalog_table" "alb_access_logs" {
  name          = "alb_access_logs"
  database_name = aws_glue_catalog_database.logs.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${var.alb_logs_bucket}/alb-access-logs/AWSLogs/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.RegexSerDe"
      parameters = {
        "serialization.format" = "1"
        "input.regex"          = local.alb_log_regex
      }
    }

    dynamic "columns" {
      for_each = local.alb_log_columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }
}

# ---- 자주 쓰는 분석 쿼리 (Athena 콘솔에 저장됨) ----
resource "aws_athena_named_query" "status_dist" {
  name        = "${var.prefix}-status-distribution"
  database    = aws_glue_catalog_database.logs.name
  workgroup   = aws_athena_workgroup.main.name
  description = "상태코드 분포"
  query       = "SELECT elb_status_code, count(*) AS cnt FROM alb_access_logs GROUP BY elb_status_code ORDER BY cnt DESC;"
}

resource "aws_athena_named_query" "ua_top" {
  name        = "${var.prefix}-user-agent-top"
  database    = aws_glue_catalog_database.logs.name
  workgroup   = aws_athena_workgroup.main.name
  description = "User-Agent Top 20 (정상/악성 UA 분포)"
  query       = "SELECT user_agent, count(*) AS hits FROM alb_access_logs GROUP BY user_agent ORDER BY hits DESC LIMIT 20;"
}

resource "aws_athena_named_query" "latency_p99" {
  name        = "${var.prefix}-latency-p99"
  database    = aws_glue_catalog_database.logs.name
  workgroup   = aws_athena_workgroup.main.name
  description = "URL별 p95/p99 지연 (SLO 위반 탐지)"
  query       = <<-SQL
    SELECT request_url,
           approx_percentile(target_processing_time, 0.95) AS p95,
           approx_percentile(target_processing_time, 0.99) AS p99,
           max(target_processing_time) AS max_latency
    FROM alb_access_logs
    GROUP BY request_url
    ORDER BY p99 DESC
    LIMIT 50;
  SQL
}

resource "aws_athena_named_query" "slow_requests" {
  name        = "${var.prefix}-slow-requests"
  database    = aws_glue_catalog_database.logs.name
  workgroup   = aws_athena_workgroup.main.name
  description = "5초 초과 요청 (availability 위반)"
  query       = <<-SQL
    SELECT time, client_ip, request_url, user_agent,
           (request_processing_time + target_processing_time + response_processing_time) AS total_latency,
           elb_status_code, target_status_code
    FROM alb_access_logs
    WHERE (request_processing_time + target_processing_time + response_processing_time) > 5
    ORDER BY total_latency DESC
    LIMIT 100;
  SQL
}

resource "aws_athena_named_query" "path_status" {
  name        = "${var.prefix}-path-status"
  database    = aws_glue_catalog_database.logs.name
  workgroup   = aws_athena_workgroup.main.name
  description = "API 경로별 상태코드 (403/404/5xx 분포)"
  query       = <<-SQL
    WITH api AS (
      SELECT regexp_extract(request_url, '(/v1/[a-zA-Z0-9]+|/healthcheck|/images)', 1) AS path,
             elb_status_code
      FROM alb_access_logs
    )
    SELECT path, elb_status_code, count(*) AS cnt
    FROM api GROUP BY path, elb_status_code ORDER BY cnt DESC;
  SQL
}

output "athena_workgroup" {
  value = aws_athena_workgroup.main.name
}
output "glue_database" {
  value = aws_glue_catalog_database.logs.name
}
