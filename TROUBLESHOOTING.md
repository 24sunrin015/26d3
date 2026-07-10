# TROUBLESHOOTING — 3과제 함정 모음

현장에서 빠르게 참조. 대부분은 "제공 바이너리를 받은 뒤 확인"해야 하는 항목이다.

## 배포 순서·타이밍

- **apply가 느리다**: RDS Multi-AZ 생성 10~15분, EKS 클러스터 10분, CloudFront 배포 5~15분. `make up`은 이걸 다 기다린다. 경기 시작 직후 바로 `apply`부터 걸어두는 게 이득(연수메모: 3과제는 초반 세팅 승부).
- **엔드포인트가 아직 안 뜬다**: CloudFront `Deployed` 상태까지 기다려야 200이 나온다. `make endpoint`로 주소 확인 후 `curl -I https://<domain>/healthcheck`.
- **TargetGroupBinding이 안 먹는다**: AWS LB Controller가 먼저 떠 있어야 CRD가 존재한다. 반드시 `addons`(컨트롤러) → `deploy`(앱) 순서. `make k8s`가 이 순서로 실행.
- **HPA가 `<unknown>`**: metrics-server 미설치/미기동. `addons.sh`가 설치하지만 기동까지 30초쯤 걸린다. `kubectl top nodes`로 확인.

## WAF (오탐이 곧 실점)

- **이미지 업로드(PUT /v1/product)가 403**: Common 룰셋의 body 검사(`SizeRestrictions_BODY` 등)가 바이너리 이미지를 오탐. 이미 `count`로 override 했지만, 그래도 막히면 WAF 로그(Logs Insights `waf-blocked-detail`)에서 어떤 룰인지 보고 추가 override.
- **정상 트래픽이 막힌다(availability 급락)**: 정상 UA는 `Python/3.10 aiohttp` + `curl`. `blocked_user_agents` 정규식에 이게 걸리면 안 된다. 룰 배포 직후 `waf-user-agent-distribution`(Logs Insights)로 정상 UA가 BLOCK되는지 즉시 확인.
- **비정상 요청이 403이 아니라 다른 코드**: 이메일 검증은 `/v1/user` POST + JSON body 기준. body가 8KB 넘거나 content-type이 다르면 룰이 안 걸릴 수 있음.
- **미제공 경로가 403으로 나온다(404여야 함)**: `malicious_paths`가 과도하게 매칭했는지 확인. 스캐너 경로만 잡고, `/v1/none` 류는 ALB 기본동작(404)으로 흘려보내야 한다.
- **WCU 초과로 apply 실패**: Web ACL 기본 상한 1500. 관리형 4종만으로 ~1125. 커스텀까지 넘으면 SQLi(200) 룰을 빼거나 쿼터 증설. 당일 쿼터 요청은 지연되니 룰을 줄이는 쪽.

## 제공 바이너리 확인(당일 필수)

바이너리 받으면 먼저 `strings provided/product | grep -iE 'S3|BUCKET|REGION|region'` 등으로 아래를 확인:

- **product의 S3 버킷 env 키 이름**: `config.env`에 `S3_BUCKET`/`BUCKET_NAME`을 모두 넣어 뒀지만, 앱이 다른 키(`AWS_BUCKET` 등)를 읽으면 추가. IRSA로 AWS 자격증명은 자동 주입되므로 키/시크릿 env는 불필요.
- **S3 오브젝트 키 규칙**: `/images/product50001.jpg` 다운로드가 S3 어떤 키로 매핑되는지. CloudFront 함수가 `/images` 프리픽스를 **제거**하도록 기본 설정(예시 기준). 앱이 `images/` 프리픽스로 저장하면 이 함수를 빼야 한다. `curl -I https://<domain>/images/<올린파일>`로 200 확인.
- **product GET 응답에 requestid가 에코되는지**: 에코된다면 CloudFront `id` 캐싱이 다른 요청의 requestid를 되돌려줘 변조 판정 위험. 그럴 땐 product 캐시 behavior의 TTL을 0으로 낮추거나 캐싱 해제(`CachingDisabled`). 응답 body를 실제로 찍어 확인.
- **user 스키마**: 2026 과제지는 id/username/email. 2025 바이너리엔 `status_message`가 있었으니 제공본이 다르면 `init.sql`/덤프 반영 확인.

## DB

- **connection 폭주 / 5xx**: `db.t3.micro`는 max_connections가 낮다(~85). HPA로 파드가 늘면 커넥션 총합이 초과할 수 있음. RDS 대시보드 `DatabaseConnections` 감시. 앱 커넥션 풀은 바이너리 소관이라, 필요 시 파라미터그룹으로 `max_connections` 상향 검토(타입은 과제지 고정 — 변경 금지).
- **MYSQL_HOST에 엔진명 넣지 말 것**: 순수 주소(RDS endpoint address)만. `terraform output rds_address`가 그 값.

## 비용(노드 수)

- **노드가 2대를 넘어 평균이 오른다**: `k8s.io/cluster-autoscaler/*` 태그와 CA가 스케일다운을 잘 하는지 확인. `scale-down-unneeded-time=2m`로 짧게. 파드 requests가 커서 노드가 안 줄면 requests 하향.
- **배포 중 노드 급증**: RollingUpdate `maxSurge:1`, graceful 15s로 최소화. Blue/Green 금지.
- **노드 수 확인**: CloudWatch 대시보드 "EC2 노드 수" 위젯(ASG `GroupInServiceInstances`) = 비용 지표 실시간.

## 로그 분석

- **Athena에서 결과 0건**: ALB 로그가 S3에 쌓이기까지 몇 분 지연. glue 테이블은 파티션 없이 전체 스캔이라 별도 `MSCK` 불필요. `alb_access_logs` 테이블에 바로 쿼리.
- **WAF 로그**: CloudWatch Logs Insights 저장쿼리 3종(`waf-blocked-*`, `waf-user-agent-distribution`) 사용. 당일 악성 패턴 역산 → WAF 룰 보정 루프.

## 기타

- **빌드 아키텍처**: 노드는 amd64. `build-push.sh`가 `--platform linux/amd64` 고정. mac(arm64)에서 빌드해도 OK.
- **aws provider**: 공식 모듈(eks/iam 5.x) 제약으로 `~> 5.95` 고정. 6.x로 올리면 init 실패.
- **엔드포인트 제출 형식**: 프로토콜+주소만(`https://xxx.cloudfront.net`), 경로 금지. `make endpoint` 출력 그대로.
