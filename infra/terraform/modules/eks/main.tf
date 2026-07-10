variable "cluster_name" { type = string }
variable "cluster_version" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" {
  type        = list(string)
  description = "컨트롤플레인 ENI·노드가 위치할 프라이빗 서브넷"
}
variable "endpoint_public_access" {
  type    = bool
  default = true
}
variable "node_instance_type" { type = string }
variable "node_min_size" { type = number }
variable "node_max_size" { type = number }
variable "node_desired_size" { type = number }
variable "tags" {
  type    = map(string)
  default = {}
}

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
  depends_on   = [aws_eks_node_group.default]
}

# =====================================================================
# 관리형 노드그룹 (t3.medium)
# =====================================================================
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.vpc_cni, # CNI 준비 후 노드 join
  ]

  lifecycle {
    # 스케일링은 Cluster Autoscaler/HPA가 관리 → terraform이 되돌리지 않음
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# Cluster Autoscaler 오토디스커버리 태그 (관리형 NG ASG에 명시 부여)
resource "aws_autoscaling_group_tag" "ca_enabled" {
  autoscaling_group_name = aws_eks_node_group.default.resources[0].autoscaling_groups[0].name
  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "ca_cluster" {
  autoscaling_group_name = aws_eks_node_group.default.resources[0].autoscaling_groups[0].name
  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

# =====================================================================
# 출력 (레지스트리 모듈과 동일 인터페이스)
# =====================================================================
output "cluster_name" {
  value = aws_eks_cluster.this.name
}
output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}
output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}
output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}
output "node_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
output "node_asg_names" {
  value = aws_eks_node_group.default.resources[0].autoscaling_groups[*].name
}
