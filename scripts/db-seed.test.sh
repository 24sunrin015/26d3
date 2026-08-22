#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failed=0

assert_contains() {
  local file="$1" expected="$2" message="$3"
  if ! grep -Fq -- "$expected" "$file"; then
    echo "FAIL: $message"
    failed=1
  fi
}

test_public_rds() {
  assert_contains "$ROOT/infra/terraform/main.tf" \
    'subnet_ids        = module.vpc.public_subnets' \
    'RDS must use public subnets'
  assert_contains "$ROOT/infra/terraform/modules/rds/main.tf" \
    'name       = "${var.prefix}-rds-public-subnet-group"' \
    'RDS must use a separate public subnet group'
  assert_contains "$ROOT/infra/terraform/modules/rds/main.tf" \
    'publicly_accessible    = true' \
    'RDS must be publicly accessible'
  assert_contains "$ROOT/infra/terraform/modules/rds/main.tf" \
    'cidr_blocks = ["0.0.0.0/0"]' \
    'RDS port 3306 must allow public IPv4 ingress'
}

test_local_seed() {
  mkdir -p "$TMP/bin"
  printf '%s\n' '-- USER DATA --' > "$TMP/user.sql"
  printf '%s\n' '-- PRODUCT DATA --' > "$TMP/product.sql"

  cat > "$TMP/bin/terraform" <<'SH'
#!/usr/bin/env bash
case "${*: -1}" in
  rds_address) echo public-rds.example.com ;;
  db_username) echo appuser ;;
  db_name) echo dev ;;
  db_password) echo secret ;;
  *) exit 1 ;;
esac
SH
  cat > "$TMP/bin/mysql" <<'SH'
#!/usr/bin/env bash
cat > "$MYSQL_CAPTURE"
printf '%s\n' "$*" > "$MYSQL_ARGS_CAPTURE"
SH
  for blocked in kubectl aws; do
    cat > "$TMP/bin/$blocked" <<'SH'
#!/usr/bin/env bash
echo "forbidden command called: $0" >&2
exit 97
SH
  done
  chmod +x "$TMP/bin/terraform" "$TMP/bin/mysql" "$TMP/bin/kubectl" "$TMP/bin/aws"

  export MYSQL_CAPTURE="$TMP/mysql-input.sql"
  export MYSQL_ARGS_CAPTURE="$TMP/mysql-args.txt"
  PATH="$TMP/bin:$PATH" TF_DIR="$ROOT/infra/terraform" \
    bash "$ROOT/scripts/db-seed.sh" --user-dump "$TMP/user.sql" || {
      echo 'FAIL: user seed must run through local mysql without kubectl/aws'
      failed=1
      return
    }

  assert_contains "$MYSQL_CAPTURE" 'CREATE TABLE IF NOT EXISTS `user`' \
    'user seed must apply the user schema first'
  assert_contains "$MYSQL_CAPTURE" '-- USER DATA --' \
    'user seed must send the selected dump to mysql'
  if grep -Fq 'CREATE TABLE IF NOT EXISTS `product`' "$MYSQL_CAPTURE"; then
    echo 'FAIL: user-only seed must not touch the product table'
    failed=1
  fi
  assert_contains "$MYSQL_ARGS_CAPTURE" '--protocol=TCP' \
    'mysql must use a direct TCP connection'
}

test_public_rds
test_local_seed

if (( failed )); then
  exit 1
fi
echo 'PASS: public RDS and local db seed contract'
