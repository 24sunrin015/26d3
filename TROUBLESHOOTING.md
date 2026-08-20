# TROUBLESHOOTING — 3과제 함정 모음

현장에서 빠르게 참조. 대부분은 "제공 바이너리를 받은 뒤 확인"해야 하는 항목이다.

## WAF (오탐이 곧 실점)

- **이미지 업로드(PUT /v1/product)가 403**: Common 룰셋의 body 검사(`SizeRestrictions_BODY` 등)가 바이너리 이미지를 오탐. 이미 `count`로 override 했지만, 그래도 막히면 WAF 로그(Logs Insights `waf-blocked-detail`)에서 어떤 룰인지 보고 추가 override.
- **정상 트래픽이 막힌다(availability 급락)**: 정상 UA는 `Python/3.10 aiohttp` + `curl`. `blocked_user_agents` 정규식에 이게 걸리면 안 된다. 룰 배포 직후 `waf-user-agent-distribution`(Logs Insights)로 정상 UA가 BLOCK되는지 즉시 확인.
- **비정상 요청이 403이 아니라 다른 코드**: 이메일 검증은 `/v1/user` POST + JSON body 기준. body가 8KB 넘거나 content-type이 다르면 룰이 안 걸릴 수 있음.

## 제공 바이너리 확인(당일 필수)

바이너리 받으면 먼저 `strings provided/product | grep -iE 'S3|BUCKET|REGION|region'` 등으로 아래를 확인:

- **product의 S3 버킷 env 키 이름**: `config.env`에 `S3_BUCKET`/`BUCKET_NAME`을 모두 넣어 뒀지만, 앱이 다른 키(`AWS_BUCKET` 등)를 읽으면 추가. IRSA로 AWS 자격증명은 자동 주입되므로 키/시크릿 env는 불필요.
- **S3 오브젝트 키 규칙**: `/images/product50001.jpg` 다운로드가 S3 어떤 키로 매핑되는지. CloudFront 함수가 `/images` 프리픽스를 **제거**하도록 기본 설정(예시 기준). 앱이 `images/` 프리픽스로 저장하면 이 함수를 빼야 한다. `curl -I https://<domain>/images/<올린파일>`로 200 확인.

## DB

- **connection 폭주 / 5xx**: `db.t3.micro` 기본 max_connections는 낮다(~85). 튜닝 파라미터그룹에서 **200으로 상향**(메모리 여유 내). 그래도 HPA 파드가 폭증하면 부족할 수 있으니 RDS 대시보드 `DatabaseConnections` 감시. 앱 커넥션 풀은 바이너리 소관이라 근본 통제 불가 → **캐싱으로 DB read 압력을 걷어내는 게 1차 방어**. (RDS Proxy는 지연·비용 + 2025 비추천으로 미채택.)
- **DB 튜닝(파라미터그룹)**: `${prefix}-mysql80` — buffer_pool 3/8(데이터 작아 전량 캐시), `innodb_flush_log_at_trx_commit=2`·`sync_binlog=0`(쓰기 처리량↑, Multi-AZ 물리복제라 안전), gp3용 io_capacity 상향. 인스턴스 클래스가 현장에서 바뀌면 buffer_pool은 formula라 자동 스케일, `max_connections`(200)만 재검토.
- **슬로우쿼리 관측**: `long_query_time=0.1`(100ms 초과 로깅) + `error`/`slowquery` 로그를 CloudWatch로 수출(`/aws/rds/instance/<id>/slowquery`). 경기 중 병목 쿼리 즉시 확인. 커버링 인덱스가 안 먹으면 `EXPLAIN`으로 확인.
- **MYSQL_HOST에 엔진명 넣지 말 것**: 순수 주소(RDS endpoint address)만. `terraform output rds_address`가 그 값.
- **테이블 스키마도 apply 때 자동 생성 안 함**(`null_resource.db_tables` 제거 — 어차피 제공 덤프가 DROP+CREATE로 테이블을 만들기 때문에 사전 스키마 적용이 중복이었음). 스키마+데이터 모두 **`make db-seed`** 로 한 번에 적재 — `provided/load_user.dump`를 in-cluster 파드로 넣고, 날아가는 커버링 인덱스(idx_email_cover)를 idempotent 복구 + `ANALYZE`까지 한다. `modules/rds/tables/*.sql`은 참고용 스키마 문서로만 남아있음(자동 적용 안 됨).

## 비용(노드 수)

- **노드가 2대를 넘어 평균이 오른다**: `k8s.io/cluster-autoscaler/*` 태그와 CA가 스케일다운을 잘 하는지 확인. `scale-down-unneeded-time=2m`로 짧게. 파드 requests가 커서 노드가 안 줄면 requests 하향.
- **배포 중 노드 급증**: RollingUpdate `maxSurge:1`, graceful 15s로 최소화. Blue/Green 금지.
- **노드 수 확인**: CloudWatch 대시보드 "EC2 노드 수" 위젯(ASG `GroupInServiceInstances`) = 비용 지표 실시간.

## 로그 분석

- **Athena에서 결과 0건**: ALB 로그가 S3에 쌓이기까지 몇 분 지연. glue 테이블은 파티션 없이 전체 스캔이라 별도 `MSCK` 불필요. `alb_access_logs` 테이블에 바로 쿼리.
- **WAF 로그**: CloudWatch Logs Insights 저장쿼리 3종(`waf-blocked-*`, `waf-user-agent-distribution`) 사용. 당일 악성 패턴 역산 → WAF 룰 보정 루프.
- **앱 로그**: 기본은 `kubectl logs`. Container Insights는 미채택(operation-strategy §6 — CW agent가 stress CPU 반토막). CloudWatch 앱로그 집계가 꼭 필요하면 `-var enable_app_log_shipping=true`로 경량 Fluent Bit만 옵션 설치(`/aws/eks/<cluster>/workloads`). 트래픽/DB 분석은 agentless로 커버: ALB→Athena, WAF Logs Insights, RDS error/slowquery export.

### 경기 중 실시간 스케일 조절 워크플로 (metrics-server만)

경기 중 핵심 결정은 하나 — "stress가 CPU를 갉기 시작했나 → 3번째 노드(stress_node_max)로 갈까". CloudWatch(1분+ 지연)로는 60초 붕괴를 놓치므로 **metrics-server로만** 판단한다.

- **관측**: `kubectl top pods -l app=stress` / `k9s` / `kubectl top nodes` / `kubectl get hpa -w`. metrics-server는 kubelet 직독이라 지연 없음, 모든 노드 커버.
- **stress가 튀면**: 이미 HPA(target 85%)→Pending→CA가 자동으로 stress 노드를 2대까지 올린다. 수동 개입 필요 시 `kubectl edit hpa stress`(max↑) 또는 `stress_node_max`↑ 후 `make apply`.
- **비용 판단**: `kubectl top nodes`로 stress 노드가 계속 포화면 length가 흉악한 것 → 3노드 허용(cost 2점 손실 < stress 5점 방어, §5). 순하면 2노드 유지.
- user/product는 sleep이라 CPU ~0 → 스케일 불필요, 노드 A 1대 고정.

## 기타

- **빌드 아키텍처**: 노드는 amd64. `build-push.sh`가 `--platform linux/amd64` 고정. mac(arm64)에서 빌드해도 OK.
- **aws provider**: 공식 모듈(eks/iam 5.x) 제약으로 `~> 5.95` 고정. 6.x로 올리면 init 실패.
- **엔드포인트 제출 형식**: 프로토콜+주소만(`https://xxx.cloudfront.net`), 경로 금지. `make endpoint` 출력 그대로.
