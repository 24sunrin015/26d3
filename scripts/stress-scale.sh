#!/usr/bin/env bash
set -euo pipefail

TF_DIR="${TF_DIR:-infra/terraform}"
: "${STUDENT_ID:?STUDENT_ID(비번호)가 필요합니다}"
: "${STRESS_NODES:?STRESS_NODES=1 또는 STRESS_NODES=2가 필요합니다}"

case "$STRESS_NODES" in
  1|2) ;;
  *) echo "STRESS_NODES는 1 또는 2여야 합니다"; exit 1 ;;
esac

tf() { terraform -chdir="$TF_DIR" output -raw "$1"; }
tfjson() { terraform -chdir="$TF_DIR" output -json "$1"; }

REGION="$(tf region)"
CLUSTER="$(tf cluster_name)"
ASG="$(tf stress_node_asg_name)"
TG_STRESS="$(tfjson target_group_arns | jq -r .stress)"

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

if [[ "$STRESS_NODES" == "1" ]]; then
  kubectl -n default patch hpa stress --type merge -p '{"spec":{"minReplicas":1,"maxReplicas":1}}'
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$ASG" \
    --min-size 1 \
    --max-size 2
  echo "stress scale-in 시작: HPA 1 replica, CA가 빈 stress 노드를 drain 후 축소합니다"
  exit 0
fi

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG" \
  --min-size 2 \
  --desired-capacity 2 \
  --max-size 2
kubectl -n default patch hpa stress --type merge -p '{"spec":{"minReplicas":2,"maxReplicas":2}}'

deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
  ready_nodes="$(kubectl get nodes -l role=stress -o json | jq '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length')"
  ready_pods="$(kubectl -n default get pods -l app=stress -o json | jq '[.items[] | select(.status.phase == "Running") | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length')"
  healthy_targets="$(aws elbv2 describe-target-health --target-group-arn "$TG_STRESS" --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)"

  if (( ready_nodes >= 2 && ready_pods >= 2 && healthy_targets >= 2 )); then
    echo "stress scale-out 완료: Ready nodes=$ready_nodes, Ready pods=$ready_pods, healthy targets=$healthy_targets"
    exit 0
  fi
  sleep 5
done

echo "stress scale-out 시간 초과: 120초 안에 Ready nodes/pods/healthy targets 2개를 확인하지 못했습니다"
exit 1
