#!/usr/bin/env bash
# 클러스터 부가구성 설치: kubeconfig, metrics-server, AWS LB Controller, Cluster Autoscaler.
# terraform output에서 값을 읽어 IRSA와 연결한다. 멱등(재실행 안전).
set -euo pipefail

TF_DIR="${TF_DIR:-infra/terraform}"
tf() { terraform -chdir="$TF_DIR" output -raw "$1"; }

REGION="$(tf region)"
CLUSTER="$(tf cluster_name)"
VPC_ID="$(tf vpc_id)"
LBC_ROLE="$(tf lb_controller_role_arn)"
CA_ROLE="$(tf cluster_autoscaler_role_arn)"

echo "==> kubeconfig ($CLUSTER / $REGION)"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

echo "==> metrics-server (HPA 지표)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "==> helm repos"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo add autoscaler https://kubernetes.github.io/autoscaler >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "==> AWS Load Balancer Controller (TargetGroupBinding CRD 포함)"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set-string serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$LBC_ROLE" \
  --wait

echo "==> Cluster Autoscaler"
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  -n kube-system \
  --set autoDiscovery.clusterName="$CLUSTER" \
  --set awsRegion="$REGION" \
  --set rbac.serviceAccount.create=true \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set-string rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$CA_ROLE" \
  --set extraArgs.scale-down-unneeded-time=2m \
  --set extraArgs.scale-down-delay-after-add=2m

echo "==> addons done"
