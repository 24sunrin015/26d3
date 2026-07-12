# =====================================================================
# stress 노드그룹 B — self-managed (warm pool 위해)
# terraform aws_eks_node_group은 warmPoolConfig 미지원 → ASG를 직접 만들어 warm_pool 부착.
# warm pool: 평시 Stopped 인스턴스 1대 대기(cost 0, running 카운트 제외) → CA 스케일 시 즉시 join.
# =====================================================================

# EKS 최적화 AL2023 AMI (클러스터 버전에 맞춰 SSM에서 조회)
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

# self-managed 노드용 인스턴스 프로파일 (노드 IAM 역할 래핑)
resource "aws_iam_instance_profile" "stress_node" {
  name = "${var.cluster_name}-stress-node"
  role = aws_iam_role.node.name
}

# NOTE: 노드 조인 권한(access entry)은 별도로 만들지 않는다.
# API_AND_CONFIG_MAP 모드에서 apps 관리형 노드그룹이 공유 node role(aws_iam_role.node)에
# EC2_LINUX access entry를 자동 생성하며, self-managed stress도 같은 role을 쓰므로 그 entry로 커버됨.
# (같은 principal에 access entry를 또 만들면 ResourceInUseException으로 apply 실패)

# AL2023 nodeadm 부트스트랩 — role=stress 라벨 + dedicated=stress taint로 조인
locals {
  stress_user_data = base64encode(templatefile("${path.module}/stress-userdata.tftpl", {
    cluster_name = aws_eks_cluster.this.name
    endpoint     = aws_eks_cluster.this.endpoint
    ca_data      = aws_eks_cluster.this.certificate_authority[0].data
    service_cidr = aws_eks_cluster.this.kubernetes_network_config[0].service_ipv4_cidr
  }))
}

resource "aws_launch_template" "stress" {
  name_prefix            = "${var.cluster_name}-stress-"
  image_id               = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type          = var.node_instance_type
  user_data              = local.stress_user_data
  vpc_security_group_ids = [aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.stress_node.arn
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2          # 컨테이너(aws-node 등)가 IMDS 도달하도록
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-stress" })
  }
}

resource "aws_autoscaling_group" "stress" {
  name_prefix         = "${var.cluster_name}-stress-"
  min_size            = 1
  desired_capacity    = 1
  max_size            = var.stress_node_max
  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.stress.id
    version = "$Latest"
  }

  # 평시 1대 Stopped 대기 → 스케일아웃 시 부팅 없이 즉시 join
  warm_pool {
    pool_state                  = "Stopped"
    min_size                    = 1
    max_group_prepared_capacity = var.stress_node_max
  }

  # EKS 노드 인식
  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }
  # Cluster Autoscaler 오토디스커버리
  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
  # CA가 스케일아웃 시뮬레이션에서 새 노드의 label/taint를 알도록(pending stress pod 매칭)
  tag {
    key                 = "k8s.io/cluster-autoscaler/node-template/label/role"
    value               = "stress"
    propagate_at_launch = false
  }
  tag {
    key                 = "k8s.io/cluster-autoscaler/node-template/taint/dedicated"
    value               = "stress:NoSchedule"
    propagate_at_launch = false
  }
  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-stress"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity] # CA가 관리
  }

  # apps 관리형 NG가 공유 node role의 access entry를 자동 생성 → 그 뒤에 조인
  depends_on = [aws_eks_node_group.apps]
}
