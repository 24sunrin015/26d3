#!/usr/bin/env bash
# 로컬 mysql 클라이언트로 public RDS에 스키마와 덤프를 적재.
#
# 사용:
#   scripts/db-seed.sh [--user-dump PATH] [--product-dump PATH]
#   - 각 플래그는 선택. 준 것만 적재한다(안 준 테이블은 건드리지 않음).
#   - 둘 다 안 주면 아무것도 적재하지 않고 종료(덤프가 없는 날 대비).
#
# 제공 SQL은 data-only이므로 선택한 테이블의 참조 스키마를 먼저 적용한다.
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

INPUTS=()
POST_SQL=""
[[ -n "$USER_DUMP" ]] && {
  test -f "$USER_DUMP" || { echo "덤프 없음: $USER_DUMP"; exit 1; }
  INPUTS+=("$TF_DIR/modules/rds/tables/user.sql" "$USER_DUMP")
  POST_SQL+=$'ANALYZE TABLE `user`;\n'
}
[[ -n "$PRODUCT_DUMP" ]] && {
  test -f "$PRODUCT_DUMP" || { echo "덤프 없음: $PRODUCT_DUMP"; exit 1; }
  INPUTS+=("$TF_DIR/modules/rds/tables/product.sql" "$PRODUCT_DUMP")
  POST_SQL+=$'ANALYZE TABLE `product`;\n'
}

if [[ ${#INPUTS[@]} -eq 0 ]]; then
  echo "적재할 덤프 미지정(--user-dump / --product-dump). 데이터 주입 없이 종료."
  exit 0
fi

HOST="$(tf rds_address)"
DBUSER="$(tf db_username)"
DBNAME="$(tf db_name)"
DBPASS="$(tf db_password)"

command -v mysql >/dev/null || { echo "로컬 mysql 클라이언트가 필요합니다"; exit 1; }

echo "==> local mysql: seeding '$DBNAME' from: ${INPUTS[*]}"
cat "${INPUTS[@]}" <(printf '%s' "$POST_SQL") | MYSQL_PWD="$DBPASS" mysql --protocol=TCP \
  -h "$HOST" -P 3306 -u "$DBUSER" "$DBNAME"

echo "==> db-seed done"
