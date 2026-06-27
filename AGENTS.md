# 3과제 작업 지침 — System Operation

> 상위 지침: [`../AGENTS.md`](../AGENTS.md). 충돌 시 우선순위: **task.md > 본 문서 > ../AGENTS.md**.
> **채점 해석(cost ratio·availability·performance 산식, 트래픽 스펙)은 [`taskfiles/guide.md`](taskfiles/guide.md)에 상세히 있다. 작업 전 반드시 읽는다.**

---

## 1. 과제 성격 (확정 과제)

- **과제명**: System Operation — task1/2와 달리 **이미 확정된 단일 과제**다.
- **경기시간**: 3시간
- **형태**: 운영형. 시스템을 구축한 뒤 **경기 시작 1시간 후 주입되는 트래픽**을 SLO에 맞게 처리한다.
- **채점**: 트래픽 주입 결과 로그(`results_<비번호>.log`) 기반 **자동 채점, 총 40점**. 상세는 `guide.md`.
- **리전**: ap-northeast-2.

## 2. 아키텍처 제약 (위반 시 0점 — guide.md 6장과 동일)

| 구분 | 규정 | 위반 시 |
|---|---|---|
| 컴퓨팅 | EC2만. **Fargate/Lambda 전면 금지** | Lambda 부적절 사용 시 전체 0점 |
| 오케스트레이션 | **EKS** (ECS 금지) | 항목 0점 |
| EC2 타입 | `t3.medium` (※ 현장에서 변경 가능 — task.md 따름) | 감점/0점 |
| DB | `db.t3.micro`, Multi-AZ, MySQL 8.0, gp3. **user·product 모두 RDS** | 성능+비용 항목 0점 |
| S3 | 이미지 저장/다운로드 (2026 신규) | image 처리율 감점 |

> **2025 대비 변경**: ECS→**EKS**, product DynamoDB→**RDS**, **S3 이미지 신규**. 작년 코드를 그대로 쓰지 않는다.

## 3. 채점 핵심 (요약 — 상세 guide.md)

- **cost ratio = 트래픽 구간 평균 EC2 노드 수 / baseline(2대)**. 1.0 이하 만점, 0.5 미만 탈락. 노드 적을수록 고득점. (단 performance 3종 ≥30% 게이트)
- **availability**: 5초 내 2xx 성공률. **performance**: SLO 내 응답률(user·product ≤0.2s, stress ≤1.0s).
- **비정상 요청**: image 처리율 + 이메일검증/403·404 (WAF 레벨 구현).

→ **운영 전략**: 노드 평균 2대 이하 유지 + HPA/Cluster Autoscaler로 피크에만 스케일아웃. product는 캐싱으로 SLO 달성. (guide.md 7장)

### ★ 악성 트래픽 방어 — 구현 전 반드시 사용자와 의논 (TODO)

악성 트래픽은 **User-Agent 등 헤더에 이상값을 박는** 형태다(2025-game 바이너리 리버싱으로 확인 가능). 선수 시스템은 이를 **WAF 등으로 방어**해 403으로 차단해야 한다. 공격 생성은 `task3-author/loadgen`, 방어는 여기(task3) — **양쪽에 걸친 설계다.**

**구체적 공격 헤더 패턴·방어 규칙은 미확정. 착수 전 사용자와 반드시 의논한다(단독 진행 금지).**

## 4. ★ 지급파일 특수 케이스 (현장 10분 전 지급)

3과제 앱 바이너리(user/product/stress)는 **경기 시작 10분 전 현장 지급**이다.

- **앱 소스는 선수 레포에 없다.** demo 앱 소스·부하주입기·채점기는 **출제자 측 `task3-author/`(별도 레포)** 에 있고, 선수 레포(task3)에는 **빌드된 바이너리만** `provided/`로 들어온다(실제 대회와 동일).
- **훈련 시**: `task3-author`에서 `make publish` → demo 바이너리(Go)가 `provided/`로 복사된다. (작년 바이너리는 `analysis/2025-game/`에 있으나 2026 스펙과 다름 — product가 RDS·S3로 바뀜.)
- **현장 시**: 지급 바이너리를 `provided/`에 넣는다.
- 훈련/현장 모두 **`provided/`에서 배포**한다(분기 없음). 차이는 "누가 만든 바이너리냐"뿐.

## 4-1. 이중 blocker (현장 사고 방지)

`make up/apply/k8s`는 아래 둘이 모두 충족돼야 진행된다.

- **STUDENT_ID 미설정** → 중단 (비번호는 `TF_VAR_student_id`로 전파, 상위 지침 6.6).
- **`provided/`에 바이너리(user·product·stress) 누락** → 중단.

## 5. 디렉토리 구조

```
task3/                # 선수 레포 (바이너리만)
├── Makefile          # up/down/.../k8s — STUDENT_ID + 바이너리 이중 blocker
├── infra/            # 테라폼 (VPC/EKS/RDS/S3/ECR + 모니터링). local state
├── k8s/              # 매니페스트 (kustomize) — Deployment/HPA/Service
├── provided/         # 앱 바이너리 (git 제외). 훈련=publish, 현장=지급
├── analysis/         # 2025 기출 분석 (참고용, 배포 대상 아님)
└── taskfiles/        # 과제지·채점기준표·guide.md·images

task3-author/         # 출제자 측 (별도 레포, 선수에 노출 금지)
├── apps/{user,product,stress}/  # demo 앱 소스 (Go/Gin)
├── loadgen/          # 부하 주입기 (Python/aiohttp)
├── grader/           # 채점기 (results_<비번호>.log 생성·집계)
└── Makefile          # build → publish(→task3/provided) / loadgen / grade
```

## 6. 작업 방식 & 검증

- `infra/`는 `templates/base/` 기반. **local state**.
- EKS 워커는 t3.medium. 앱은 `k8s/`에 Deployment+HPA, `make k8s`로 적용.
- 모니터링(트래픽 패턴·장애 감지)은 필수 요구사항 — CloudWatch 등으로 구성.
- 검증: `task3-author`에서 `make publish` → 선수 레포 `make up` → `make loadgen`(부하) → `make grade`(채점) → SLO·노드수·점수 확인. 현장에선 지급 바이너리로 교체 후 재확인.
