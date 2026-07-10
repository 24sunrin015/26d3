# =====================================================================
# 클러스터 애드온 — helm_release로 선언적 관리 (IRSA는 이 모듈 내부에서 생성)
# 컨트롤러 IRSA를 여기서 만들어 root와의 순환의존을 피한다.
# =====================================================================

# ---- IRSA 역할 (컨트롤러용) ----
module "irsa_lb_controller" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name                              = "${var.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.this.arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

module "irsa_cluster_autoscaler" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name                        = "${var.cluster_name}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.this.arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}

# ---- 앱 로그 수집: Fluent Bit → CloudWatch Logs ----
# 경량 DaemonSet(노드당 1파드, ~50m/64Mi). 컨테이너 stdout/stderr를 CloudWatch로 전송.
# 노드 증설을 유발하지 않으므로 cost ratio에 영향 없음. IRSA로 로그 쓰기 권한만 부여.
resource "aws_iam_policy" "fluent_bit" {
  name        = "${var.cluster_name}-fluent-bit"
  description = "Fluent Bit → CloudWatch Logs 쓰기"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutRetentionPolicy",
      ]
      Resource = "*"
    }]
  })
}

module "irsa_fluent_bit" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name        = "${var.cluster_name}-fluent-bit"
  role_policy_arns = { logs = aws_iam_policy.fluent_bit.arn }

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.this.arn
      namespace_service_accounts = ["kube-system:aws-for-fluent-bit"]
    }
  }
}

resource "helm_release" "fluent_bit" {
  name       = "aws-for-fluent-bit"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  version    = "0.1.34"
  namespace  = "kube-system"

  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-for-fluent-bit"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa_fluent_bit.iam_role_arn
  }

  # CloudWatch Logs만 사용(나머지 출력 비활성 = 경량)
  set {
    name  = "cloudWatchLogs.enabled"
    value = "true"
  }
  set {
    name  = "cloudWatchLogs.region"
    value = var.region
  }
  set {
    name  = "cloudWatchLogs.logGroupName"
    value = "/aws/eks/${var.cluster_name}/workloads"
  }
  set {
    name  = "cloudWatchLogs.logStreamPrefix"
    value = "app-"
  }
  set {
    name  = "cloudWatchLogs.autoCreateGroup"
    value = "true"
  }
  set {
    name  = "cloudWatchLogs.logRetentionDays"
    value = "7"
  }
  set {
    name  = "firehose.enabled"
    value = "false"
  }
  set {
    name  = "kinesis.enabled"
    value = "false"
  }
  set {
    name  = "elasticsearch.enabled"
    value = "false"
  }

  # 경량 리소스 (워크로드 자원 보존)
  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }
  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }
  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }

  depends_on = [aws_eks_node_group.default]
}

# ---- helm_release ----
# HPA 지표 공급
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
  namespace  = "kube-system"

  depends_on = [aws_eks_node_group.default]
}

# AWS Load Balancer Controller (TargetGroupBinding CRD 제공)
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.1"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = var.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa_lb_controller.iam_role_arn
  }

  depends_on = [aws_eks_node_group.default]
}

# Cluster Autoscaler (노드 스케일 — 비용 관리 핵심)
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.37.0"
  namespace  = "kube-system"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "awsRegion"
    value = var.region
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa_cluster_autoscaler.iam_role_arn
  }
  # 피크 후 빠르게 축소(비용 평균↓)
  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "2m"
  }
  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "2m"
  }

  depends_on = [aws_eks_node_group.default]
}
