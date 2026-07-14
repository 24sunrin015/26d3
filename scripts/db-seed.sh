#!/usr/bin/env bash
# provided/load_user.dump → RDS 적재. private RDS라 in-cluster mysql 파드로 실행.
# 스키마는 make apply(null_resource)가 이미 생성. 단, dump가 DROP+CREATE를 포함하면
# 우리 커버링 인덱스(idx_email_cover)가 날아가므로 적재 후 idempotent하게 복구 + ANALYZE.
# (dump가 data-only여도 가드로 안전 — 인덱스 있으면 스킵)
set -euo pipefail

TF_DIR="${TF_DIR:-infra/terraform}"
DUMP="${1:-provided/load_user.dump}"
tf() { terraform -chdir="$TF_DIR" output -raw "$1"; }

test -f "$DUMP" || { echo "dump 파일이 없습니다: $DUMP"; exit 1; }

CLUSTER="$(tf cluster_name)"
REGION="$(tf region)"
echo "==> kubeconfig ($CLUSTER / $REGION)"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

HOST="$(tf rds_address)"
DBUSER="$(tf db_username)"
DBNAME="$(tf db_name)"

# 적재 후 실행: 커버링 인덱스 idempotent 복구 + 옵티마이저 통계 갱신
POST_SQL=$(cat <<'SQL'
SET @x := (SELECT COUNT(*) FROM information_schema.statistics
           WHERE table_schema = DATABASE() AND table_name = 'user' AND index_name = 'idx_email_cover');
SET @s := IF(@x = 0, 'CREATE INDEX idx_email_cover ON `user` (`email`,`username`)', 'DO 0');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;
ANALYZE TABLE `user`;
ANALYZE TABLE `product`;
SQL
)

echo "==> seeding '$DBNAME' from $DUMP (in-cluster pod)"
kubectl delete pod db-seed --ignore-not-found >/dev/null 2>&1 || true
cat "$DUMP" <(printf '\n%s\n' "$POST_SQL") | kubectl run db-seed --rm -i --restart=Never \
  --image=mysql:8.0 --env="MYSQL_PWD=$(tf db_password)" --command -- \
  mysql -h "$HOST" -P 3306 -u "$DBUSER" "$DBNAME"

echo "==> db-seed done (인덱스 복구 + ANALYZE 포함)"
