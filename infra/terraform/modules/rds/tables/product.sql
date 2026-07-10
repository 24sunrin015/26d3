-- product 테이블 — 과제지 §3 스키마 준수
-- 모든 접근이 id(PK) 기준: GET ?id= / POST(생성) / PUT(image_path 갱신).
-- → 보조 인덱스 불필요(쓰기 오버헤드 최소). 반복 조회는 CloudFront id-키 캐싱이 흡수.
CREATE TABLE IF NOT EXISTS `product` (
  `id`         VARCHAR(255) NOT NULL,
  `name`       VARCHAR(255) NOT NULL,
  `price`      FLOAT(8) NOT NULL,
  `image_path` VARCHAR(500) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;

ANALYZE TABLE `product`;
