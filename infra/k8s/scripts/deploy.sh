#!/usr/bin/env bash
# terraform output → k8s 주입: config/secret env 생성, 템플릿 렌더, kubectl apply -k.
set -euo pipefail

TF_DIR="${TF_DIR:-infra/terraform}"
OVL="${OVL:-infra/k8s/overlays/prod}"
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
TG_USER="$(tfjson target_group_arns | jq -r .user)"
TG_PRODUCT="$(tfjson target_group_arns | jq -r .product)"
TG_STRESS="$(tfjson target_group_arns | jq -r .stress)"
PRODUCT_ROLE_ARN="$(tf app_s3_role_arn)"

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
export ECR_USER ECR_PRODUCT ECR_STRESS TG_USER TG_PRODUCT TG_STRESS PRODUCT_ROLE_ARN
render() {
  python3 -c 'import os,sys,re; s=open(sys.argv[1]).read(); sys.stdout.write(re.sub(r"\$\{(\w+)\}", lambda m: os.environ.get(m.group(1),""), s))' "$1"
}
for t in kustomization targetgroupbindings sa-patch; do
  render "$OVL/$t.yaml.tmpl" > "$OVL/$t.yaml"
done

echo "==> kubectl apply -k $OVL"
kubectl apply -k "$OVL"

echo "==> rollout 대기"
kubectl -n default rollout status deploy/user --timeout=180s
kubectl -n default rollout status deploy/product --timeout=180s
kubectl -n default rollout status deploy/stress --timeout=180s
echo "==> deploy done"
