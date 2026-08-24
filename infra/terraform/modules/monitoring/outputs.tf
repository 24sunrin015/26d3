output "athena_workgroup" {
  value = aws_athena_workgroup.main.name
}
output "glue_database" {
  value = aws_glue_catalog_database.logs.name
}

locals {
  dashboard_url_base = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name="
}

output "dashboard_urls" {
  description = "ops(기존) + svc/db/nodes/security(신규) 대시보드 콘솔 URL"
  value = {
    ops      = "${local.dashboard_url_base}${aws_cloudwatch_dashboard.main.dashboard_name}"
    svc      = "${local.dashboard_url_base}${aws_cloudwatch_dashboard.svc.dashboard_name}"
    db       = "${local.dashboard_url_base}${aws_cloudwatch_dashboard.db.dashboard_name}"
    nodes    = "${local.dashboard_url_base}${aws_cloudwatch_dashboard.nodes.dashboard_name}"
    security = "${local.dashboard_url_base}${aws_cloudwatch_dashboard.security.dashboard_name}"
  }
}
