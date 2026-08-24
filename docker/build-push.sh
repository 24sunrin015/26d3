#!/usr/bin/env bash
# provided/ 바이너리 + docker/Dockerfile을 zip으로 묶어 S3에 올리고
# CodeBuild가 이미지를 빌드해 ECR에 푸시하도록 트리거한다.
# 로컬 Docker 불필요(현장에서 로컬 Docker 사용이 어려운 상황 대응, EC2 빌드 인스턴스도 안 씀).
set -euo pipefail

TF_DIR="${TF_DIR:-infra/terraform}"
APPS=(user product stress)

if [[ -n "${EXTRA_APPS:-}" ]]; then
  IFS=',' read -r -a extras <<< "$EXTRA_APPS"
  for app in "${extras[@]}"; do
    [[ "$app" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "잘못된 EXTRA_APPS 이름: $app"; exit 1; }
    APPS+=("$app")
  done
fi

tf() { terraform -chdir="$TF_DIR" output -raw "$1"; }

for app in "${APPS[@]}"; do
  test -f "provided/$app" || { echo "provided/$app 바이너리가 없습니다"; exit 1; }
done

BUCKET="$(tf codebuild_source_bucket)"
KEY="$(tf codebuild_source_key)"
PROJECT="$(tf codebuild_project_name)"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
ZIP="$WORKDIR/source.zip"

echo "==> 소스 압축: 앱 바이너리와 hedger 소스"
zip -q -r "$ZIP" docker/Dockerfile apps/hedger "${APPS[@]/#/provided/}"

echo "==> S3 업로드 (s3://$BUCKET/$KEY)"
aws s3 cp "$ZIP" "s3://$BUCKET/$KEY" --only-show-errors

echo "==> CodeBuild 시작 ($PROJECT)"
BUILD_ID="$(aws codebuild start-build --project-name "$PROJECT" --query 'build.id' --output text)"
echo "    build id: $BUILD_ID"

STATUS="IN_PROGRESS"
while [[ "$STATUS" == "IN_PROGRESS" ]]; do
  sleep 5
  STATUS="$(aws codebuild batch-get-builds --ids "$BUILD_ID" --query 'builds[0].buildStatus' --output text)"
  echo "    status: $STATUS"
done

if [[ "$STATUS" != "SUCCEEDED" ]]; then
  echo "==> 빌드 실패($STATUS). 로그:"
  aws codebuild batch-get-builds --ids "$BUILD_ID" \
    --query 'builds[0].logs.{group:groupName,stream:streamName,link:deepLink}' --output table
  exit 1
fi
echo "==> images done (CodeBuild)"
