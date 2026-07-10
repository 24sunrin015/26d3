#!/usr/bin/env bash
# provided/ 바이너리를 이미지로 빌드해 ECR에 푸시. 노드가 amd64이므로 --platform 고정.
set -euo pipefail

TF_DIR="${TF_DIR:-infra/terraform}"
APPS=(user product stress)

REGION="$(terraform -chdir="$TF_DIR" output -raw region)"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

echo "==> ECR 로그인 ($REGISTRY)"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for app in "${APPS[@]}"; do
  test -f "provided/$app" || { echo "provided/$app 바이너리가 없습니다"; exit 1; }
  url="$(terraform -chdir="$TF_DIR" output -json ecr_repository_urls | jq -r ".$app")"
  echo "==> build & push: $app → $url:latest"
  docker build --platform linux/amd64 -f docker/Dockerfile --build-arg "APP=$app" -t "$url:latest" .
  docker push "$url:latest"
done
echo "==> images done"
