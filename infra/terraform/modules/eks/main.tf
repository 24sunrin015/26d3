data "aws_partition" "current" {}

# =====================================================================
# 클러스터 IAM 역할
# =====================================================================
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# =====================================================================
# EKS 클러스터
# =====================================================================
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true # 생성자에 kubectl 관리권한
  }

  # 컨트롤플레인 로그 → CloudWatch (관리형, 노드 자원 소비 0)
  # 관측성 최대화: API/audit/authenticator/controllerManager/scheduler 전량
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags       = var.tags
  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# =====================================================================
# IRSA용 OIDC 공급자
# =====================================================================
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

# =====================================================================
# 노드 IAM 역할
# =====================================================================
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

# =====================================================================
# 애드온 — vpc-cni는 노드보다 먼저, coredns는 노드 이후
# =====================================================================
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"
  tags         = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
  tags         = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
  tags         = var.tags
  depends_on   = [aws_eks_node_group.apps, aws_eks_node_group.stress]
}

# =====================================================================
# 관리형 노드그룹 2개 (t3.medium) — operation-strategy §4
#  A(apps): user/product 격리, 고정 1대 (sleep이라 CPU 0, 스케일 불필요)
#  B(stress): stress 격리, min1/max2 + taint로 stress 전용, CA가 스케일
# =====================================================================
resource "aws_eks_node_group" "apps" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "apps"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    min_size     = var.apps_node_count
    max_size     = var.apps_node_count
    desired_size = var.apps_node_count
  }

  update_config {
    max_unavailable = 1
  }

  labels = { role = "apps" }
  tags   = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.vpc_cni,
  ]
}

resource "aws_eks_node_group" "stress" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "stress"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    min_size     = 1
    max_size     = var.stress_node_max
    desired_size = 1
  }

  update_config {
    max_unavailable = 1
  }

  labels = { role = "stress" }

  # stress 전용 노드: 이 taint를 toleration하는 stress pod만 스케줄됨
  taint {
    key    = "dedicated"
    value  = "stress"
    effect = "NO_SCHEDULE"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.vpc_cni,
  ]

  lifecycle {
    # 스케일링은 CA/HPA가 관리 → terraform이 되돌리지 않음
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# Cluster Autoscaler 오토디스커버리 태그 — 스케일 대상은 stress 그룹뿐
resource "aws_autoscaling_group_tag" "ca_enabled" {
  autoscaling_group_name = aws_eks_node_group.stress.resources[0].autoscaling_groups[0].name
  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "ca_cluster" {
  autoscaling_group_name = aws_eks_node_group.stress.resources[0].autoscaling_groups[0].name
  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}
