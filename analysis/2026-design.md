# 2026 3과제 (System Operation) — 분석 & 설계 노트

> 2025 기출(로그·바이너리·연수메모) 분석과 2026 과제지·채점기준을 종합한 설계 기준 문서.
> 인프라/매니페스트/WAF/관측성 구현은 모두 이 문서를 근거로 한다.
> 근거 출처: `taskfiles/{task,mark,guide}.md`, `analysis/2025-game/`, 2025 레퍼런스 레포 `ninejuan/2025-day3`(WAF·연수메모·Athena).

---

## 1. 채점 구조 (총 40점)

| 항목 | 배점 | 지표(results 로그 키) | 세부 |
|---|---|---|---|
| 1. 비정상 요청 처리 | 4 | `image download`, `Exception Handling` | 각 0.5 × 8 (임계 90/85/80/50%) |
| 2. 고가용성 | 12 | `(user/product/stress) availability` | 각 0.5 × 24 (임계 90~30%) |
| 3. 성능 효율성 | 12 | `(user/product/stress) performance` | 각 0.5 × 24 (SLO 내 응답률) |
| 4. 비용 최적화 | 12 | `cost ratio` | 각 1.0 × 12 (성능 3종 ≥30% 게이트) |

- **cost ratio = 트래픽 구간 평균 EC2 워커노드 수 / 2(baseline)**. 지속측정 평균. `≤1.00`이면 12점 만점, `<0.50`이면 전 항목 0점.
- **비용 게이트**: user·product·stress performance가 모두 ≥30%여야 비용 점수 인정. 노드 과소로 성능 붕괴 시 비용도 0.
- SLO: user·product **≤0.2s**, stress **≤1.0s**, availability는 전 API **≤5s 2xx**.
- 측정은 전부 **클라이언트 도착 기준**(end-to-end, 네트워크 지연 포함) → 엣지 지연이 점수에 직결.

**함의**: 노드 평균을 2대 근처로 눌러 비용 만점을 노리되, 성능 게이트(≥30%)와 실제 SLO(≥90% 목표)를 동시에 만족해야 한다. product는 캐싱으로 DB·노드 부하를 걷어내는 게 핵심 지렛대.

---

## 2. 트래픽 분석

### 2.1 2025 실측 (WAF 로그 200건 샘플, 약 13분 구간)

| 구분 | 관측 |
|---|---|
| 정상 UA | `Python/3.10 aiohttp/3.12.15` (189/200) — 채점 부하주입기 |
| 그 외 UA | curl(healthcheck/grader용), Chrome(브라우저 확인) |
| 메서드 | POST 191 : GET 9 — **쓰기 우세** |
| 경로 | `/v1/user` 161, `/v1/product` 33, `/v1/stress` 2, `/healthcheck` 2 |
| 출발지 | KR 199 / GB 1 |
| 유입 경로 | CloudFront → ALB (X-Forwarded-For, Via 헤더 존재) |
| 차단 | 1건뿐 — IP 직접접근 스캐너(User-Agent 없음, `AWSManagedRulesCommonRuleSet`의 `NoUserAgent_HEADER`) |

### 2.2 2026 가정 (사용자 확정)

- **트래픽 규모 = 2025 × 1.0 ~ 1.5배.** 스케일 설계·부하 재현 시 이 배율 적용.
- 정상 트래픽은 aiohttp UA로 대량 유입 → **aiohttp UA 자체를 차단하면 정상 트래픽이 죽는다.** UA 기반 차단은 "명백한 악성 시그니처"에만 한정.
- 실제 악성 주입 패턴은 이 로그 창에 거의 안 잡힘 → **당일 주입 전까지 미지수.** 따라서 WAF는 특정 시그니처 의존이 아니라 **다층 방어**로 폭넓게 막는다(§5).

---

## 3. 앱 / DB 동작 & 2026 변경점

### 3.1 앱 (2025 바이너리 정적분석으로 확인)

- 3앱 공통: `/healthcheck` GET → `{"status":"ok."}`, 바인딩 **TCP/8080**, access log stdout/stderr.
- DB 연결 env: `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_HOST`(IP/DNS, 엔진명 금지), `MYSQL_PORT`, `MYSQL_DBNAME`(=`dev`).
- 모든 요청에 변조방지용 `requestid`, `uuid` 포함 → **정상 요청의 Req/Res를 건드리면 감점.** WAF는 이 필드를 변형하지 않는다.
- user: `GET /v1/user?email=..`, `POST /v1/user`(username·email).
- product: `GET/POST /v1/product`, **2026 신규 `PUT /v1/product`(이미지 포함, multipart)**.
- stress: `POST /v1/stress`(length) — CPU 부하 유발용.

### 3.2 2025 → 2026 변경 (작년 코드 그대로 쓰면 안 되는 지점)

| 영역 | 2025 | 2026 |
|---|---|---|
| 오케스트레이션 | ECS | **EKS** (ECS 금지) |
| product 저장소 | DynamoDB | **RDS(MySQL)** — user·product 둘 다 RDS |
| 이미지 | (없음/DynamoDB) | **S3** 업로드 + `/images/<obj>` 다운로드 |
| user 스키마 | id·username·email·**status_message** | id·username·email (status_message 제거) |
| EC2 타입 | c5.large 등 | **t3.medium** (현장 변경 가능) |

- 2026 DB 스키마(과제지):
  ```sql
  CREATE TABLE user (id VARCHAR(255) PK, username VARCHAR(255) NOT NULL UNIQUE, email VARCHAR(255) NOT NULL);
  CREATE TABLE product (id VARCHAR(255) PK, name VARCHAR(255) NOT NULL, price FLOAT(8) NOT NULL, image_path VARCHAR(500) DEFAULT NULL);
  ```
- `load_user.dump`로 시드 데이터 삽입(수정·삭제 금지). 시드 외 임의 데이터 삽입 금지(성능저하). **트래픽 패턴에 맞게 테이블 구조 재설계 여지** 명시됨 → 인덱스 튜닝 정도(예: product.id는 이미 PK, user.email 조회 잦으면 인덱스 검토).

---

## 4. 목표 아키텍처

```
                 (단일 엔드포인트: https://<cf-domain>)
                              │
                    ┌─────────▼──────────┐
                    │     CloudFront     │  캐싱(product GET), 엣지 종단
                    └───┬────────────┬───┘
          default behavior          /images/*  behavior
                    │                    │
             ┌──────▼──────┐      ┌───────▼───────┐
             │  ALB (WAF)  │      │   S3 (OAC)    │  정적 이미지 다운로드
             └──────┬──────┘      └───────────────┘
                    │ (WAF: 403/404/이메일검증/악성차단)
             ┌──────▼───────────────────────┐
             │  EKS (t3.medium 워커, 노드 ~2)│
             │  user / product / stress Deploy + HPA │
             └──────┬───────────────────────┘
                    │ (product는 S3 PutObject로 이미지 업로드)
             ┌──────▼──────┐        ┌────────────┐
             │ RDS MySQL   │        │     S3     │
             │ Multi-AZ    │        │ (images)   │
             │ db.t3.micro │        └────────────┘
             └─────────────┘
```

**핵심 설계 결정**

1. **단일 엔드포인트 = CloudFront 도메인.** 프로토콜+주소만 제출(경로 금지). ALB/S3는 뒤에 숨김.
2. **/images/\* 다운로드는 CloudFront → S3(OAC) 직결** — ALB/앱/WAF를 안 거침. 캐시 히트로 빠르고, 노드 부하 0. S3 버킷은 퍼블릭 비공개 + CloudFront OAC로만 접근.
3. **이미지 업로드(PUT /v1/product)는 CloudFront → ALB → 앱 → 앱이 S3 PutObject.** 앱 파드는 IRSA(IAM Role for ServiceAccount)로 S3 권한 획득(액세스키 하드코딩 금지).
4. **product GET 캐싱**이 성능·비용 동시 지렛대. 동일 id 반복 조회가 잦다(과제지 명시) → CloudFront 캐시 정책에 `id` 쿼리 포함, 짧은 TTL. 캐시 히트는 DB·노드를 안 건드리고 ≤0.2s 달성.
5. **WAF는 ALB에 REGIONAL로 부착**(2025 동일, ap-northeast-2 유지). API 경로만 WAF 통과, /images는 미해당.
6. **비용**: NAT는 최소화(가능하면 단일 NAT or VPC 엔드포인트로 대체 검토), bastion 대신 **SSM Session Manager**. 워커노드는 관리형 노드그룹 + Cluster Autoscaler/Karpenter, 앱은 HPA.

---

## 5. WAF 다층 방어 설계 (핵심 요구사항)

> 사용자 지시: **"최대한 다양하게 막아라."** 2026 악성 패턴 미지수 전제. 2025 레퍼런스(`ninejuan/2025-day3 modules/waf`)를 확장·고도화한다.

### 5.1 응답코드 규칙 (과제지 §7 — 반드시 준수)

- **제공 API 경로로의 비정상 요청 → 403** (WAF block = 기본 403).
- **미제공 경로(예 `/v1/none`) → 404.** ⇒ **미제공 경로는 WAF로 막지 않는다**(막으면 403이 됨). 앱/ALB가 자연스럽게 404를 내도록 통과시킨다. (2025의 PathWhitelist 룰을 주석처리한 이유와 동일 — 이 원칙 유지)
- 잘못된 이메일 형식(`gildong`, `gildong@example`) → **403** (앱엔 검증 없음 → WAF에서 구현).

### 5.2 룰 구성 (우선순위 순)

| P | 룰 | 동작 | 내용 |
|---|---|---|---|
| 1 | `AWSManagedRulesCommonRuleSet` | 관리형 | 단, **body 검사 룰은 이미지 업로드 오탐 위험**(§5.4) → 해당 룰 override |
| 2 | `AWSManagedRulesKnownBadInputsRuleSet` | 관리형 | 알려진 악성 입력 |
| 3 | `AWSManagedRulesSQLiRuleSet` | 관리형 | SQLi (여유 WCU 봐서 유지/제외 결정) |
| 4 | `AWSManagedRulesAmazonIpReputationList` | 관리형(신규) | 평판 나쁜 IP (25 WCU, 저렴) |
| 10 | MethodWhitelist | block | GET/POST/PUT/HEAD/OPTIONS 외 차단 (2026은 PUT 추가) |
| 20 | RateLimit | block(rate) | IP당 요청률 상한 — 플러딩/DoS성 억제 (rate-based, 2 WCU) |
| ~~30~~ | ~~MaliciousPathBlock~~ | — | **폐기**: `wp-admin`/`.env`/`phpmyadmin` 등도 결국 "미제공 경로"라 §7 규정상 403이 아니라 404여야 함(2025 PathWhitelist와 동일 실수). 룰 제거, ALB 기본 404로 통과 |
| 40 | UserEmailValidation | block | `/v1/user` POST + JSON body가 유효 이메일 정규식 **불일치** 시 차단 |
| 50 | BlockedUserAgents | block | 명백한 악성 UA 시그니처 정규식 (aiohttp/curl 정상 UA는 **제외**) |
| 60 | SuspiciousHeaders | block | 이상 헤더값(빈 Host, 비정상 Content-Length, 알려진 공격도구 헤더 등) 다수 패턴 |

- **정규식 세트 분할**: AWS WAF regex pattern set은 세트당 최대 10개 정규식. "다양하게"를 위해 **주제별 세트 여러 개**(bad-ua / scanner-paths / injection-markers / bad-headers)로 나눠 각 룰이 참조. 세트를 늘려 패턴 커버리지를 넓힌다.
- 모든 룰 `visibility_config`로 CloudWatch 메트릭 + 샘플 요청 활성화(관측성·튜닝).

### 5.3 WCU 예산 (Web ACL 기본 상한 1,500)

| 룰 | 대략 WCU |
|---|---|
| CommonRuleSet | 700 |
| KnownBadInputs | 200 |
| SQLi | 200 |
| AmazonIpReputationList | 25 |
| 커스텀(byte/regex/rate 합) | ~150–300 |
| **합계** | **~1,300–1,400 (상한 내)** |

- 커스텀 룰의 정확한 소비량은 `terraform apply` 후 콘솔/`aws wafv2` 로 확인. 상한 초과 시: (a) SQLi 룰 제외 또는 (b) WCU 상한 증설 쿼터 요청. **당일엔 쿼터 요청 지연 위험 → 기본 1,500 내로 설계.**

### 5.4 ★ 이미지 업로드 오탐 (반드시 처리할 함정)

- `PUT /v1/product`(이미지 multipart)는 CloudFront→ALB→WAF를 통과한다. CommonRuleSet의 **`SizeRestrictions_BODY`**(8KB 초과 body 차단)와 **body 검사 룰**(`CrossSiteScripting_BODY`, `GenericRFI_BODY`, `GenericLFI_BODY`)이 **바이너리 이미지 데이터를 오탐**해 정상 업로드를 403으로 죽일 수 있다 → `image` 처리율 하락.
- **대응**: 관리형 그룹의 해당 룰을 `rule_action_override`로 **Count**(비차단) 전환하거나, 이미지 업로드 경로(`method=PUT AND uri=/v1/product`)에 대해 body 검사 룰이 적용되지 않도록 scope-down. 다운로드(/images/\*)는 CloudFront→S3 직결이라 WAF 미해당(문제 없음).
- WAF body 검사 기본 상한(ALB 8KB) 확인 — 이메일 검증은 작은 JSON이라 무관, 이미지 업로드는 위 override로 회피.

### 5.5 WAF 로깅

- WAF → CloudWatch Logs(`aws-waf-logs-*`) 로깅 설정. **전량(KEEP) 로깅** 후 Athena로 분석(§6.3). (2025는 BLOCK만 로깅 → 2026은 전량 로깅으로 정상/차단 분포까지 분석 = 고도화.)

---

## 6. 관측성 설계 (CloudWatch 중심, 2025 대비 고도화)

> 사용자 지시: CloudWatch 중심 + **WAF/ALB 로그를 Athena로 쿼리해 User-Agent 등 분석**. 2025보다 제대로.

### 6.1 메트릭 & 대시보드 (CloudWatch)

- **EKS Container Insights**: 노드/파드 CPU·메모리·네트워크, 파드 재시작. (노드 수 추적 = 비용 지표 자가검증)
- **ALB 메트릭**: `TargetResponseTime`(p50/p90/**p99**), `HTTPCode_Target_2XX/4XX/5XX`, `HTTPCode_ELB_5XX`, `RequestCount`, `HealthyHostCount`, `RejectedConnectionCount`.
- **RDS**: CPU, `DatabaseConnections`, read/write latency, freeable memory.
- **CloudFront**: 요청수, 캐시 **HitRate**(product 캐싱 효과 검증), 4xx/5xx.
- **WAF**: 룰별 Allowed/Blocked 카운트(어떤 룰이 얼마나 막는지).
- 통합 대시보드 1개(서비스/DB/엣지/WAF 4섹션) + **RED 관점**(Rate·Error·Duration). 평균이 아닌 **p99** 중심(1건 초장기 응답으로 SLO 깨지는 것 탐지).

### 6.2 알람 (장애/오류 빠른 감지 — 과제 요구)

- ALB 5xx > 0 (연수메모: **500 에러 0 원칙**), Target 4xx 급증.
- `TargetResponseTime` p99 > 임계(user/product 0.2s, stress 1.0s 근처에서 경보).
- `HealthyHostCount` < 1, `UnHealthyHostCount` > 0.
- RDS CPU/connections 임계, CloudFront 캐시 히트율 급락(캐싱 붕괴 = 성능/비용 동반 악화).
- 알람 → (선택) SNS. 현장에선 대시보드 상시 관찰이 1차.

### 6.3 로그 분석 (Athena)

- **ALB access log** → S3 → Athena 외부테이블(RegexSerDe). 2025 `docs/Athena.md`의 테이블 DDL·쿼리집 재사용/개선:
  - 상태코드 분포, URL별 hits, **UA Top-N**, path별 status, **p95/p99 지연**, 5초 초과 요청, 5xx 요청.
- **WAF log** → CloudWatch Logs → S3(또는 Firehose) → Athena. 쿼리:
  - 차단된 요청의 **User-Agent/헤더/경로 분포**(당일 악성 패턴 실시간 역산 → WAF 룰 즉시 보정).
  - 룰별 차단 비율, 오탐 의심(정상 UA가 차단됐는지) 탐지.
- 목적: 당일 트래픽 주입 후 **"어떤 악성 패턴이 실제로 오는지"를 Athena로 즉시 파악**해 WAF를 반복 튜닝(이번 설계의 고도화 포인트).

### 6.4 앱 로그

- 앱 stdout/stderr → EKS → CloudWatch Logs(Fluent Bit / Container Insights). 서버 레벨 에러 추적(Athena는 ALB/WAF, 서버 500은 앱 로그).

---

## 7. 비용 · 스케일링 · 배포 전략

- **노드 평균 ≤2대**가 비용 만점 관건. 상시 2대(또는 그 이하)로 시작, **피크에만 스케일아웃** 후 복귀(지속측정 평균이라 잠깐 늘려도 평균 관리 가능).
- **HPA**(파드) + **Cluster Autoscaler/Karpenter**(노드). 스케일인도 적극적으로(불필요 노드 즉시 회수 = 평균↓).
- **product 캐싱으로 노드 수요 자체를 줄인다** — 캐시 히트가 앱/DB를 안 건드리므로 같은 트래픽을 더 적은 노드로 소화.
- **Rolling 업데이트**(Blue/Green은 EC2 2배 → 비용 감점). **graceful shutdown 텀은 짧게**(앱 응답 빠름 → 긴 텀 불필요, 길면 배포 중 노드 증가로 비용 감점). Readiness/Liveness 프로브 정교화(ALB fail-open 대비 — unhealthy 파드로 트래픽 안 가게).
- **바이너리 배포 속도**: 현장 지급(10분 전) 즉시 이미지 빌드→ECR 푸시→롤아웃이 빨라야 초반 요청 점수 확보. `provided/`에서 배포하는 파이프라인을 미리 검증.
- 500 에러 0 원칙, 4xx도 최소화(정상 트래픽 오탐 방지 = WAF 튜닝과 직결).

---

## 8. 리스크 / 오픈 이슈

1. **WAF 이미지 업로드 오탐**(§5.4) — 미처리 시 image 점수 직접 손실. 최우선 검증 대상.
2. **WAF 정상 UA 오탐** — aiohttp/curl 정상 트래픽을 악성 룰이 막으면 availability/performance 동반 붕괴. 룰 배포 후 Athena로 즉시 검증.
3. **CloudFront 캐싱과 정합성** — POST/PUT은 절대 캐시 금지, GET만. 캐시 키에 id 포함. 잘못 캐싱하면 변조/오응답으로 감점.
4. **db.t3.micro Multi-AZ 성능 한계** — 트래픽 1.5배 시 DB 병목 가능. 캐싱으로 read 부하를 최대한 걷어내고, 커넥션 수/슬로우쿼리 모니터링. DB 타입은 과제지 고정(변경 시 성능·비용 0점).
5. **엔드포인트 제출 형식** — 프로토콜+주소만, 경로 금지. 위반 시 전 항목 0점.
6. **인스턴스 타입 현장 변경 가능성** — t3.medium은 과제지값. 현장에서 바뀌면 `task.md` 우선, 변수로 처리해 즉시 대응.
7. **STUDENT_ID 하드코딩 금지** — 리소스명·인증 등 전부 `TF_VAR_student_id`/env로 전파(Makefile blocker 이미 존재).

---

## 부록 A. 검증 루프 (목표주도)

```
1. task3-author에서 바이너리 publish (훈련) → provided/ 채움
2. export STUDENT_ID=<비번호> && make up   → 검증: terraform apply clean, 파드 Running, ALB/CF 200
3. make loadgen (부하)                      → 검증: 트래픽 유입, 대시보드 정상
4. make grade                               → 검증: results 로그 — availability/performance ≥ 목표, cost ratio ≤ 1.0
5. WAF 튜닝: Athena로 차단/오탐 분석 → 룰 보정 → 재채점
```
반복해 40점 만점 수렴. (`../task3-author`는 열람하지 않고 make 인터페이스로만 사용)
