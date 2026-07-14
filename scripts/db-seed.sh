#!/usr/bin/env bash
# 덤프를 RDS에 적재. private RDS라 in-cluster mysql 파드로 실행.
#
# 사용:
#   scripts/db-seed.sh [--user-dump PATH] [--product-dump PATH]
#   - 각 플래그는 선택. 준 것만 적재한다(안 준 테이블은 건드리지 않음).
#   - 둘 다 안 주면 아무것도 적재하지 않고 종료(덤프가 없는 날 대비).
#
# 스키마는 make apply(null_resource)가 이미 생성해 둠. 덤프가 테이블을 DROP+CREATE하면
# 커버링 인덱스(idx_email_cover)가 날아가므로, 적재 후 information_schema 가드로 idempotent
# 복구 + ANALYZE. (덤프가 data-only여도, 안 줘도 안전 — 인덱스 있으면 스킵)
set -euo pipefail

TF_DIR="${TF_DIR:-infra/terraform}"
tf() { terraform -chdir="$TF_DIR" output -raw "$1"; }

USER_DUMP=""
PRODUCT_DUMP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user-dump=*)    USER_DUMP="${1#*=}"; shift ;;
    --user-dump)      USER_DUMP="${2:-}"; shift 2 ;;
    --product-dump=*) PRODUCT_DUMP="${1#*=}"; shift ;;
    --product-dump)   PRODUCT_DUMP="${2:-}"; shift 2 ;;
    -h|--help)        echo "usage: db-seed.sh [--user-dump PATH] [--product-dump PATH]"; exit 0 ;;
    *)                echo "unknown arg: $1"; exit 1 ;;
  esac
done

DUMPS=()
[[ -n "$USER_DUMP" ]]    && { test -f "$USER_DUMP"    || { echo "덤프 없음: $USER_DUMP"; exit 1; }; DUMPS+=("$USER_DUMP"); }
[[ -n "$PRODUCT_DUMP" ]] && { test -f "$PRODUCT_DUMP" || { echo "덤프 없음: $PRODUCT_DUMP"; exit 1; }; DUMPS+=("$PRODUCT_DUMP"); }

if [[ ${#DUMPS[@]} -eq 0 ]]; then
  echo "적재할 덤프 미지정(--user-dump / --product-dump). 데이터 주입 없이 종료."
  exit 0
fi

CLUSTER="$(tf cluster_name)"
REGION="$(tf region)"
echo "==> kubeconfig ($CLUSTER / $REGION)"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

HOST="$(tf rds_address)"
DBUSER="$(tf db_username)"
DBNAME="$(tf db_name)"

# 적재 후: user 커버링 인덱스 idempotent 복구 + 통계 갱신. (없거나 이미 있으면 안전)
POST_SQL=$(cat <<'SQL'
SET @x := (SELECT COUNT(*) FROM information_schema.statistics
           WHERE table_schema = DATABASE() AND table_name = 'user' AND index_name = 'idx_email_cover');
SET @s := IF(@x = 0, 'CREATE INDEX idx_email_cover ON `user` (`email`,`username`)', 'DO 0');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;
ANALYZE TABLE `user`;
ANALYZE TABLE `product`;
SQL
)

echo "==> seeding '$DBNAME' from: ${DUMPS[*]}"
kubectl delete pod db-seed --ignore-not-found >/dev/null 2>&1 || true
cat "${DUMPS[@]}" <(printf '\n%s\n' "$POST_SQL") | kubectl run db-seed --rm -i --restart=Never \
  --image=mysql:8.0 --env="MYSQL_PWD=$(tf db_password)" --command -- \
  mysql -h "$HOST" -P 3306 -u "$DBUSER" "$DBNAME"

echo "==> db-seed done (인덱스 복구 + ANALYZE 포함)"
