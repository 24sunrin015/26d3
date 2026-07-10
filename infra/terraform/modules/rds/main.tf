resource "aws_db_subnet_group" "this" {
  name       = "${var.prefix}-rds-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "rds" {
  name        = "${var.prefix}-rds-sg"
  description = "RDS MySQL - allow 3306 from EKS nodes"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "rds_ingress" {
  for_each = toset(var.ingress_sg_ids)

  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = each.value
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # 과제지 고정 사양
  multi_az          = true
  storage_type      = "gp3"
  allocated_storage = var.allocated_storage

  db_name  = var.db_name
  username = var.username
  password = var.password
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # 대회 운영 편의 (clean apply/destroy)
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  # CloudWatch로 성능 관측
  performance_insights_enabled = true
}

# =====================================================================
# DB 테이블 자동 반영 — RDS·클러스터 ready 후 스키마만 적용
# (데이터 적재 load_user.dump는 자동으로 넣지 않는다 — 과제지: 수동 적재)
# private RDS라 in-cluster에 일회성 mysql 파드를 띄워 노드(=RDS 허용 SG)에서 적용.
# 스키마 파일(tables/*.sql) 변경 시 자동 재적용.
# =====================================================================
resource "null_resource" "db_tables" {
  triggers = {
    db_instance = aws_db_instance.this.id
    nodes       = join(",", var.node_asgs) # 노드 준비 후 실행 보장
    user_sql    = filesha256("${path.module}/tables/user.sql")
    product_sql = filesha256("${path.module}/tables/product.sql")
  }

  depends_on = [aws_db_instance.this]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      DB_PWD = var.password
    }
    command = <<-EOT
      set -euo pipefail
      aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region} >/dev/null
      echo "[db_tables] applying schema to ${aws_db_instance.this.address} via in-cluster pod ..."
      kubectl delete pod db-tables-init --ignore-not-found >/dev/null 2>&1 || true
      cat "${path.module}/tables/user.sql" "${path.module}/tables/product.sql" \
        | kubectl run db-tables-init --rm -i --restart=Never --image=mysql:8.0 \
            --env=MYSQL_PWD="$DB_PWD" --command -- \
            mysql -h ${aws_db_instance.this.address} -P ${aws_db_instance.this.port} -u ${var.username} ${var.db_name}
      echo "[db_tables] done — 데이터 적재는 수동(load_user.dump)"
    EOT
  }
}
