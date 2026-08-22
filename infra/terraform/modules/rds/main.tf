resource "aws_db_subnet_group" "this" {
  name       = "${var.prefix}-rds-public-subnet-group"
  subnet_ids = var.subnet_ids

  lifecycle {
    create_before_destroy = true
  }
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

# count 사용: 리스트 길이는 plan에 확정(=1), SG id 값은 apply-time이어도 인자로만 쓰여 OK.
# (for_each는 키가 apply-time unknown이라 plan 실패)
resource "aws_security_group_rule" "rds_ingress" {
  count = length(var.ingress_sg_ids)

  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = var.ingress_sg_ids[count.index]
}

resource "aws_security_group_rule" "rds_public_ingress" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  security_group_id = aws_security_group.rds.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "MySQL from public IPv4"
}

# =====================================================================
# 튜닝 파라미터그룹 — db.t3.micro(2vCPU/1GiB) 고정 사양 내 최대 성능
# 데이터셋이 작아(시드 수 MB) 버퍼풀이 전량 캐시 → 사실상 메모리 조회.
# 모든 값 dynamic → apply_method=immediate (재부팅 불필요).
# =====================================================================
resource "aws_db_parameter_group" "this" {
  name   = "${var.prefix}-mysql80"
  family = "mysql8.0"

  # 커넥션 — HPA 파드 다수 대비 헤드룸(메모리 여유 내). DatabaseConnections 모니터.
  parameter {
    name         = "max_connections"
    value        = "200"
    apply_method = "immediate"
  }

  # InnoDB 버퍼풀 — 데이터가 작아 3/8이면 전량 캐시 + 커넥션 메모리 여유 확보
  parameter {
    name         = "innodb_buffer_pool_size"
    value        = "{DBInstanceClassMemory*3/8}"
    apply_method = "immediate"
  }

  # 쓰기 처리량 (대회용 내구성 트레이드). Multi-AZ 인스턴스는 물리복제라 binlog 무관 → sync_binlog=0 안전.
  parameter {
    name         = "innodb_flush_log_at_trx_commit"
    value        = "2"
    apply_method = "immediate"
  }
  parameter {
    name         = "sync_binlog"
    value        = "0"
    apply_method = "immediate"
  }

  # SSD(gp3) 최적화 — 이웃 플러시 끄고 IO capacity 상향
  parameter {
    name         = "innodb_flush_neighbors"
    value        = "0"
    apply_method = "immediate"
  }
  parameter {
    name         = "innodb_io_capacity"
    value        = "1000"
    apply_method = "immediate"
  }
  parameter {
    name         = "innodb_io_capacity_max"
    value        = "2000"
    apply_method = "immediate"
  }

  # 커넥션 처리 효율
  parameter {
    name         = "thread_cache_size"
    value        = "64"
    apply_method = "immediate"
  }
  parameter {
    name         = "table_open_cache"
    value        = "2000"
    apply_method = "immediate"
  }

  # 슬로우쿼리 관측 (100ms 초과 → 경기 중 병목 쿼리 탐지)
  parameter {
    name         = "slow_query_log"
    value        = "1"
    apply_method = "immediate"
  }
  parameter {
    name         = "long_query_time"
    value        = "0.1"
    apply_method = "immediate"
  }
  parameter {
    name         = "log_output"
    value        = "FILE"
    apply_method = "immediate"
  }
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
  publicly_accessible    = true
  parameter_group_name   = aws_db_parameter_group.this.name

  # 대회 운영 편의 (clean apply/destroy)
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  # 관측: 에러/슬로우쿼리 로그를 CloudWatch로 수출(agentless).
  # Performance Insights는 db.t3.micro 미지원(InvalidParameterCombination) → 미사용.
  # DB 지표는 CloudWatch AWS/RDS 네임스페이스(CPU/connections 등)로 대체.
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
}
