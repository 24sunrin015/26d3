# =====================================================================
# 노드/비용 심화 대시보드 — ops의 "EC2 노드 수" 위젯 하나를 apps/stress
# 분리 + 노드별 CPU(AWS/EC2, AutoScalingGroupName 차원) + NAT 처리 바이트
# (숨은 비용) + CodeBuild 빌드 결과까지 전개.
# =====================================================================
locals {
  nodes_apps_asg_metrics = concat(
    [for asg in var.apps_node_asg_names : ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", asg, { label = "apps in-service" }]],
    [for asg in var.apps_node_asg_names : ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", asg, { label = "apps desired" }]],
  )
  nodes_stress_asg_metrics = [
    ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.stress_node_asg_name, { label = "stress in-service" }],
    ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", var.stress_node_asg_name, { label = "stress desired" }],
    ["AWS/AutoScaling", "GroupPendingInstances", "AutoScalingGroupName", var.stress_node_asg_name, { label = "stress pending (warm pool 제외)" }],
  ]

  nodes_ec2_cpu_metrics = concat(
    [for asg in var.apps_node_asg_names : ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", asg, { label = "apps node CPU%" }]],
    [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.stress_node_asg_name, { label = "stress node CPU%" }]],
  )

  nodes_nat_metrics = concat(
    [for id in var.nat_gateway_ids : ["AWS/NATGateway", "BytesOutToDestination", "NatGatewayId", id, { label = "out (${id})" }]],
    [for id in var.nat_gateway_ids : ["AWS/NATGateway", "BytesInFromSource", "NatGatewayId", id, { label = "in (${id})" }]],
  )

  # 전체 in-service 노드 수(apps+stress) — cost ratio 산식의 분자, baseline=2 라인 대비
  nodes_total_metrics = [
    ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", element(var.apps_node_asg_names, 0), { id = "m1", visible = false }],
    ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.stress_node_asg_name, { id = "m2", visible = false }],
    [{ expression = "m1+m2", label = "총 in-service 노드 (baseline 2)", id = "e1" }],
  ]

  dashboard_nodes_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title = "apps 노드그룹 (desired/in-service)", metrics = local.nodes_apps_asg_metrics,
          view  = "timeSeries", stat = "Average", period = 60, region = var.region, yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title = "stress 노드그룹 (desired/in-service/pending, warm pool 제외 정상)", metrics = local.nodes_stress_asg_metrics,
          view  = "timeSeries", stat = "Average", period = 60, region = var.region, yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title = "노드그룹별 CPU (AWS/EC2, 격리된 노드라 앱 CPU 근사치)", metrics = local.nodes_ec2_cpu_metrics,
          view  = "timeSeries", stat = "Average", period = 300, region = var.region
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title = "NAT Gateway 처리 바이트 (숨은 비용 — cost ratio 산식 밖)", metrics = local.nodes_nat_metrics,
          view  = "timeSeries", stat = "Sum", period = 300, region = var.region
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 24, height = 6,
        properties = {
          title       = "총 in-service 노드 수 (cost ratio 분자, baseline 2)",
          metrics     = local.nodes_total_metrics,
          view        = "timeSeries", stat = "Average", period = 60, region = var.region,
          yAxis       = { left = { min = 0 } },
          annotations = { horizontal = [{ label = "baseline 2", value = 2 }] }
        }
      },
      {
        type = "metric", x = 0, y = 18, width = 12, height = 6,
        properties = {
          title = "CodeBuild 이미지 빌드 결과", region = var.region, view = "timeSeries", stat = "Sum", period = 300,
          metrics = [
            ["AWS/CodeBuild", "SucceededBuilds", "ProjectName", var.codebuild_project_name, { label = "succeeded" }],
            [".", "FailedBuilds", ".", ".", { label = "failed" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 18, width = 12, height = 6,
        properties = {
          title   = "CodeBuild 빌드 소요시간", region = var.region, view = "timeSeries", stat = "Average", period = 300,
          metrics = [["AWS/CodeBuild", "Duration", "ProjectName", var.codebuild_project_name, { label = "duration(s)" }]]
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "nodes" {
  dashboard_name = "${var.prefix}-nodes"
  dashboard_body = local.dashboard_nodes_body
}
