#!/usr/bin/env bash
# terraform output → k8s 주입: config/secret env 생성, 템플릿 렌더, kubectl apply -k.
set -euo pipefail

TF_DIR="${TF_DIR:-infra/terraform}"
OVL="${OVL:-infra/k8s/overlays/prod}"
RESTART="${RESTART:-true}"
: "${STUDENT_ID:?STUDENT_ID(비번호)가 필요합니다}"

tf()     { terraform -chdir="$TF_DIR" output -raw "$1"; }
tfjson() { terraform -chdir="$TF_DIR" output -json "$1"; }

REGION="$(tf region)"
CLUSTER="$(tf cluster_name)"

echo "==> kubeconfig ($CLUSTER / $REGION)"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

RDS_HOST="$(tf rds_address)"
RDS_PORT="$(tf rds_port)"
DBNAME="$(tf db_name)"
DBUSER="$(tf db_username)"
DBPASS="$(tf db_password)"
BUCKET="$(tf s3_bucket)"

ECR_USER="$(tfjson ecr_repository_urls | jq -r .user)"
ECR_PRODUCT="$(tfjson ecr_repository_urls | jq -r .product)"
ECR_STRESS="$(tfjson ecr_repository_urls | jq -r .stress)"
ECR_HEDGER="$(tfjson ecr_repository_urls | jq -r .hedger)"
ECR_APPS="$(tfjson ecr_repository_urls)"
TG_USER="$(tfjson target_group_arns | jq -r .user)"
TG_PRODUCT="$(tfjson target_group_arns | jq -r .product)"
TG_STRESS="$(tfjson target_group_arns | jq -r .stress)"
TG_HEDGER="$(tf hedger_target_group_arn)"
TG_APPS="$(tfjson target_group_arns)"
PRODUCT_ROLE_ARN="$(tf app_s3_role_arn)"

EXTRA_DEPLOYMENTS=()
if [[ -n "${EXTRA_APPS:-}" ]]; then
  IFS=',' read -r -a EXTRA_DEPLOYMENTS <<< "$EXTRA_APPS"
  for app in "${EXTRA_DEPLOYMENTS[@]}"; do
    [[ "$app" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "잘못된 EXTRA_APPS 이름: $app"; exit 1; }
  done
fi

echo "==> config.env / secret.env 생성"
cat > "$OVL/config.env" <<EOF
MYSQL_USER=$DBUSER
MYSQL_HOST=$RDS_HOST
MYSQL_PORT=$RDS_PORT
MYSQL_DBNAME=$DBNAME
S3_BUCKET=$BUCKET
BUCKET_NAME=$BUCKET
AWS_REGION=$REGION
AWS_DEFAULT_REGION=$REGION
STUDENT_ID=$STUDENT_ID
EOF

cat > "$OVL/secret.env" <<EOF
MYSQL_PASSWORD=$DBPASS
EOF

echo "==> 템플릿 렌더 (kustomization / targetgroupbindings / sa-patch)"
export ECR_USER ECR_PRODUCT ECR_STRESS ECR_HEDGER TG_USER TG_PRODUCT TG_STRESS TG_HEDGER PRODUCT_ROLE_ARN
render() {
  python3 -c 'import os,sys,re; s=open(sys.argv[1]).read(); sys.stdout.write(re.sub(r"\$\{(\w+)\}", lambda m: os.environ.get(m.group(1),""), s))' "$1"
}
for t in kustomization targetgroupbindings sa-patch; do
  render "$OVL/$t.yaml.tmpl" > "$OVL/$t.yaml"
done

if [[ ${#EXTRA_DEPLOYMENTS[@]} -eq 0 ]]; then
  cat > "$OVL/extra-apps.yaml" <<EOF
apiVersion: v1
kind: List
items: []
EOF
else
  cat > "$OVL/extra-apps.yaml" <<EOF
apiVersion: v1
kind: List
items:
EOF
fi

for app in "${EXTRA_DEPLOYMENTS[@]}"; do
  image="$(jq -r --arg app "$app" '.[$app] // empty' <<< "$ECR_APPS")"
  target_group_arn="$(jq -r --arg app "$app" '.[$app] // empty' <<< "$TG_APPS")"
  [[ -n "$image" && -n "$target_group_arn" ]] || { echo "Terraform에 추가 앱이 없습니다: $app"; exit 1; }

  cat >> "$OVL/extra-apps.yaml" <<EOF
- apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: $app
    labels: { app: $app }
  spec:
    replicas: 1
    selector:
      matchLabels: { app: $app }
    template:
      metadata:
        labels: { app: $app }
      spec:
        nodeSelector: { role: apps }
        containers:
          - name: $app
            image: $image:latest
            ports:
              - { name: http, containerPort: 8080 }
            envFrom:
              - configMapRef: { name: app-config }
              - secretRef: { name: app-secret }
            resources:
              requests: { cpu: 256m, memory: 256Mi }
              limits: { cpu: 512m, memory: 512Mi }
            readinessProbe:
              httpGet: { path: /healthcheck, port: http }
              initialDelaySeconds: 3
              periodSeconds: 5
              timeoutSeconds: 2
            livenessProbe:
              httpGet: { path: /healthcheck, port: http }
              initialDelaySeconds: 10
              periodSeconds: 10
              timeoutSeconds: 3
- apiVersion: v1
  kind: Service
  metadata:
    name: $app
    labels: { app: $app }
  spec:
    type: ClusterIP
    selector: { app: $app }
    ports:
      - { name: http, port: 8080, targetPort: http }
EOF

  cat >> "$OVL/targetgroupbindings.yaml" <<EOF
---
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: $app
spec:
  serviceRef:
    name: $app
    port: 8080
  targetGroupARN: $target_group_arn
  targetType: ip
EOF
done

echo "==> kubectl apply -k $OVL"
kubectl apply -k "$OVL"

if [[ "$RESTART" == "true" ]]; then
  echo "==> rollout restart (재배포 시 새 이미지 강제 pull)"
  kubectl -n default rollout restart deployment/hedger deployment/user deployment/product deployment/stress "${EXTRA_DEPLOYMENTS[@]}"
fi

echo "==> rollout 대기"
kubectl -n default rollout status deploy/user --timeout=180s
kubectl -n default rollout status deploy/product --timeout=180s
kubectl -n default rollout status deploy/stress --timeout=180s
kubectl -n default rollout status deploy/hedger --timeout=180s
for app in "${EXTRA_DEPLOYMENTS[@]}"; do
  kubectl -n default rollout status "deploy/$app" --timeout=180s
done
echo "==> deploy done"
