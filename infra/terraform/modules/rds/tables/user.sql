-- user 테이블 — 과제지 §3 스키마 준수 + 읽기경로 최적화
-- 핫패스: GET /v1/user?email=  → email 조회.
-- 커버링 인덱스 (email, username): InnoDB 보조인덱스는 PK(id)를 암묵 포함하므로
-- (email, username, id) 전 컬럼이 인덱스에 존재 → email 조회를 index-only로 처리(테이블 접근 0).
CREATE TABLE IF NOT EXISTS `user` (
  `id`       VARCHAR(255) NOT NULL,
  `username` VARCHAR(255) NOT NULL,
  `email`    VARCHAR(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_username` (`username`),
  KEY `idx_email_cover` (`email`, `username`)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;

-- 옵티마이저 통계 갱신 (시드 적재 후 재실행 권장)
ANALYZE TABLE `user`;
