variable "student_id" {
  description = "비번호 (현장 당일 배정). Makefile이 TF_VAR_student_id로 전달. 하드코딩 금지."
  type        = string

  validation {
    condition     = length(var.student_id) > 0
    error_message = "STUDENT_ID(비번호)가 비어 있습니다. 'export STUDENT_ID=<비번호>' 후 실행하세요."
  }
}

variable "region" {
  description = "리소스를 생성할 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "name_prefix" {
  description = "리소스 이름 접두어. RDS identifier(apdev-rds-instance) 등 과제지 고정 이름과 정합."
  type        = string
  default     = "apdev"
}

# ---- 네트워크 ----
variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "사용할 가용영역 수 (Multi-AZ RDS·EKS 위해 최소 2)"
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "NAT Gateway 단일화 여부(비용 절감). NAT는 cost ratio 산식 미포함이나 계정 비용 한도 고려."
  type        = bool
  default     = true
}

# ---- EKS ----
variable "cluster_version" {
  description = "EKS 쿠버네티스 버전. 2026-07 지원: 1.36/1.35/1.34/1.33(1.33은 곧 EOL). CA 차트 appVersion과 정렬돼 1.35 사용."
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "EKS 워커노드 인스턴스 타입. 과제지 고정값(t3.medium). 현장 변경 시 여기만 수정."
  type        = string
  default     = "t3.medium"
}

# 노드그룹 2개 전략(operation-strategy §4): apps 고정 1대 + stress min1/max2.
# 평시 2노드(baseline) → 피크 최대 3노드.
variable "stress_node_max" {
  description = "stress 노드그룹 최대 대수. cost vs stress 트레이드오프(§5)에서 조절. 기본 2(총 3노드)."
  type        = number
  default     = 2
}

# ---- RDS (과제지 고정: db.t3.micro / Multi-AZ / MySQL 8.0 / gp3) ----
variable "db_instance_class" {
  description = "RDS 인스턴스 클래스. 과제지 고정(db.t3.micro). 현장 변경 시 여기만 수정."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "MySQL Community 엔진 버전"
  type        = string
  default     = "8.0"
}

variable "db_name" {
  description = "논리적 DB 이름 (앱 MYSQL_DBNAME)"
  type        = string
  default     = "dev"
}

variable "db_username" {
  description = "DB 마스터/앱 유저명"
  type        = string
  default     = "appuser"
}

variable "db_allocated_storage" {
  description = "RDS 스토리지 (GB, gp3)"
  type        = number
  default     = 20
}

# ---- 관측성 ----
# CI(Container Insights)는 미채택(operation-strategy §6). 관측은 metrics-server + agentless 로그.
variable "enable_app_log_shipping" {
  description = "앱 컨테이너 로그 CloudWatch 전송(경량 Fluent Bit, 옵션). 기본 false."
  type        = bool
  default     = false
}
