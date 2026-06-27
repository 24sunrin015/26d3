# 3과제 — System Operation (선수 풀이)

운영형 과제. 시스템을 구축하고 경기 시작 1시간 뒤 주입되는 트래픽을 SLO에 맞게 처리한다.
채점 해석(cost ratio·SLO·트래픽)은 [`taskfiles/guide.md`](taskfiles/guide.md), 작업 규칙은 [`AGENTS.md`](AGENTS.md) 참고.

## 현장 풀이 순서

```bash
export STUDENT_ID=<비번호>          # 1) 비번호 주입 (안 하면 모든 make가 막힘)

# 2) 앱 바이너리 확보 — provided/ 에 user, product, stress 3개
#    현장: 지급 바이너리를 provided/ 에 복사
#    훈련: cd ../task3-author && make publish  (빌드 후 자동 복사)

make up                           # 3) init → apply → (k8s 있으면) k8s
                                  #    바이너리 없으면 여기서 막힘
make down                         # 철거 (k8s 먼저 정리 후 destroy)
```

## 안전장치 (현장 사고 방지)

- **STUDENT_ID 미설정 시**: `make up/plan/apply/...` 즉시 중단.
- **provided/ 바이너리(user·product·stress) 누락 시**: `make up/apply/k8s` 중단.
- 둘 다 채워야만 인프라가 반영된다.

## 디렉토리

| 경로 | 내용 |
|---|---|
| `infra/` | 테라폼 (VPC/EKS/RDS/S3/ECR + 모니터링). local state |
| `k8s/` | 매니페스트 (kustomize) — Deployment/HPA/Service |
| `provided/` | 앱 바이너리 (git 제외, 현장/훈련에 채움) |
| `taskfiles/` | 과제지·채점기준표·guide.md |
| `analysis/` | 2025 기출 분석 (참고용) |

> 앱 소스와 부하 주입기·채점기는 **출제자 측 `task3-author/`(별도 레포)** 에 있다. 선수 레포(여기)에는 바이너리만 들어온다.

---

## 과제지 vs 채점기준표 충돌 내역

(없음. 발견 시 여기에 기재한다.)
