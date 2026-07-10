#!/usr/bin/env bash
# 제공 이미지(수천 개)를 S3에 대량 업로드. 콘솔 수동 업로드는 사고 → 스크립트로 병렬 sync.
#
# 키 레이아웃: CloudFront /images/* 는 '/images' 프리픽스를 벗겨 S3 키에 매핑한다.
#   예) 다운로드 <endpoint>/images/product50001.jpg  →  S3 key: product50001.jpg
# 따라서 소스 디렉토리를 버킷 루트로 sync 한다(하위 경로 구조는 그대로 보존).
#
# 사용: bash scripts/upload_images.sh [소스디렉토리]   (기본: provided/images)
set -euo pipefail

TF_DIR="${TF_DIR:-infra/terraform}"
SRC="${1:-provided/images}"

BUCKET="$(terraform -chdir="$TF_DIR" output -raw s3_bucket)"

test -d "$SRC" || { echo "이미지 소스 디렉토리가 없습니다: $SRC"; exit 1; }

count="$(find "$SRC" -type f | wc -l | tr -d ' ')"
echo "==> $count files: $SRC → s3://$BUCKET/  (CloudFront /images/* 로 서빙)"

# 대량 파일 병렬 처리 튜닝
aws configure set default.s3.max_concurrent_requests 20

aws s3 sync "$SRC" "s3://$BUCKET/" --only-show-errors
echo "==> 업로드 완료. 확인: curl -I \"\$(make -s endpoint | tail -1)/images/<파일명>\""
