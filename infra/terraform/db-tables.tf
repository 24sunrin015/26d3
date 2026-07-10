# =====================================================================
# DB 테이블 자동 반영 — RDS·클러스터 ready 후 스키마만 적용
# (데이터 적재 load_user.dump는 자동으로 넣지 않는다 — 과제지: 수동 적재)
#
# private RDS라 러너에서 직접 못 붙으므로, in-cluster에 일회성 mysql 파드를 띄워
# 노드(=RDS 허용 SG)에서 스키마를 적용한다. 로컬 mysql/도커·SG 변경 불필요.
# 스키마 파일(modules/rds/tables/*.sql) 변경 시 자동 재적용.
# =====================================================================
resource "null_resource" "db_tables" {
  triggers = {
    db_instance = module.rds.identifier
    user_sql    = filesha256("${path.module}/modules/rds/tables/user.sql")
    product_sql = filesha256("${path.module}/modules/rds/tables/product.sql")
  }

  depends_on = [module.rds, module.eks]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      DB_PWD = random_password.db.result
    }
    command = <<-EOT
      set -euo pipefail
      aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} >/dev/null
      echo "[db_tables] applying schema to ${module.rds.address} via in-cluster pod ..."
      kubectl delete pod db-tables-init --ignore-not-found >/dev/null 2>&1 || true
      cat "${path.module}/modules/rds/tables/user.sql" "${path.module}/modules/rds/tables/product.sql" \
        | kubectl run db-tables-init --rm -i --restart=Never --image=mysql:8.0 \
            --env=MYSQL_PWD="$DB_PWD" --command -- \
            mysql -h ${module.rds.address} -P ${module.rds.port} -u ${var.db_username} ${var.db_name}
      echo "[db_tables] done — 데이터 적재는 수동(load_user.dump)"
    EOT
  }
}
