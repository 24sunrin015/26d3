# 3과제 — System Operation (선수 풀이)

운영형 과제. 시스템을 구축하고 경기 시작 1시간 뒤 주입되는 트래픽을 SLO에 맞게 처리한다.
설계 근거는 [`analysis/2026-design.md`](analysis/2026-design.md), 채점 해석은 [`taskfiles/guide.md`](taskfiles/guide.md), 작업 규칙은 [`AGENTS.md`](AGENTS.md).

## 아키텍처

```
사용자 → CloudFront(단일 엔드포인트) ─┬─ default/·/v1/*  → ALB(+WAF) → EKS(user·product·stress)
                                     └─ /images/*       → S3 (OAC)
EKS → RDS(MySQL Multi-AZ) / product는 S3로 이미지 업로드(IRSA)
```

- **ALB·타겟그룹은 Terraform이 소유**, EKS 파드는 `TargetGroupBinding`으로 등록 → 단일 apply로 재현.
- product GET은 CloudFront에서 `id` 키로 캐싱(SLO·비용), `/images`는 S3 직결 캐싱.
- 비정상 요청은 WAF에서 403, 미제공 경로는 ALB에서 404.

## 현장 풀이 순서

```bash
export STUDENT_ID=<비번호>          # 1) 비번호 주입 (안 하면 모든 make가 막힘)

# 2) 앱 바이너리 확보 — provided/ 에 user, product, stress 3개
#    현장: 지급 바이너리를 provided/ 에 복사
#    훈련: cd ../task3-author && make publish  (빌드 후 자동 복사)

make up          # init → apply(인프라+애드온) → images(ECR) → deploy(앱) → 엔드포인트 출력
make endpoint    # 제출용 단일 엔드포인트 다시 출력
make down        # 전체 철거 (terraform destroy)
```

단계별로도 실행 가능: `make apply` → `make images` → `make deploy`.
클러스터 애드온(LB Controller·Cluster Autoscaler·metrics-server)은 Terraform `helm_release`(`infra/terraform/addons.tf`)로 `apply` 시 함께 설치된다.

## 안전장치 (현장 사고 방지)

- **STUDENT_ID 미설정 시**: 모든 `make` 타깃 즉시 중단.
- **provided/ 바이너리 누락 시**: `make up/images/deploy` 중단.
- 비번호는 `TF_VAR_student_id`로 terraform에, `config.env`로 k8s에 전파(SSOT는 `STUDENT_ID` 하나).

## 디렉토리

| 경로 | 내용 |
|---|---|
| `infra/terraform/` | 테라폼 (VPC/EKS/RDS/S3/ECR/ALB/WAF/CloudFront/monitoring). local state |
| `infra/k8s/` | kustomize (base + overlays/prod) + deploy.sh (output→렌더→apply) |
| `docker/` | Dockerfile + build-push.sh (provided 바이너리 → ECR) |
| `provided/` | 앱 바이너리 (git 제외, 현장/훈련에 채움) |
| `analysis/` | 2025 기출 분석 + 2026 설계 노트 |
| `taskfiles/` | 과제지·채점기준표·guide.md |

배포 검증: [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) 참고. 앱 소스·부하주입기·채점기는 출제자 측 `task3-author/`(별도 레포)에 있고 여기엔 바이너리만 들어온다.

---

## 과제지 vs 채점기준표 충돌 내역

(없음. 발견 시 여기에 기재한다.)
