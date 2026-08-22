# 추가 API binary 현장 대응표

새 binary는 기존 user/product/stress를 교체하지 않는 네 번째 API다. 실제 경로가 `/v1/newapp`이든 `/v2/product`이든 이름과 경로를 새 workload로 취급한다. 기존 `/v1/user`, `/v1/product`, `/v1/stress`, RDS MySQL, S3 image 경로는 건드리지 않는다.

현재 과제지에서 user와 product는 RDS MySQL을 써야 한다. 새 binary가 DynamoDB, DocumentDB, ElastiCache를 요구하더라도 user/product의 RDS를 대체하거나 없애면 안 된다. 새 저장소는 **새 binary가 실제로 필요하다고 확인된 경우에만** 추가한다. 과제지에 없는 관리형 DB/cache를 미리 만들면 비용제한과 불필요 리소스 감점 위험만 생긴다.

## 현재 배치부터 기억

```text
apps node group: t3.medium 1대 고정
  ├─ user    request/limit 512m / 512Mi
  └─ product request/limit 512m / 512Mi

stress node group: t3.medium 1대, dedicated=stress:NoSchedule
  └─ stress request 1500m, limit 2000m
```

- user/product는 `role=apps`만 선택한다.
- stress는 별도 노드와 taint를 사용한다. 새 binary를 stress node에 얹지 않는다.
- apps node group은 현재 min=max=desired 1이다. 이 그룹에 새 Pod를 넣어도 Cluster Autoscaler가 자동으로 두 번째 apps node를 만들지 않는다.
- 새 binary의 HPA max를 무심코 2 이상으로 두면 여유가 없는 경우 Pod가 Pending으로 남고, 그 Pod가 자동으로 노드를 늘려주지 않을 수 있다.
- 비용 만점 목표는 트래픽 구간 평균 2노드다. apps를 한 대 더 고정하면 평시 3노드가 되어 cost ratio 약 1.5, 비용 점수는 10점 구간이다.

## 0~10분: binary가 무엇을 요구하는지 확인

```bash
file provided/<new-binary>
sha256sum provided/<new-binary>
strings -a provided/<new-binary> | rg -i \
  'MYSQL|RDS|DYNAMODB|DOCUMENTDB|MONGO|REDIS|ELASTICACHE|CACHE|TABLE|DB_|HOST|PORT|TLS|CA|/health|/v[0-9]/'
```

찾을 값:

| 찾는 문자열/행동 | 의미 | 다음 조치 |
| --- | --- | --- |
| `MYSQL_*`, `sql.Open`, `mysql` | RDS MySQL client 가능성 | MySQL branch 확인 |
| `DynamoDB`, `PutItem`, `Query`, `TABLE_NAME` | DynamoDB client 가능성 | DynamoDB branch 확인 |
| `DocumentDB`, `mongodb`, `MONGO_URI`, `tlsCAFile` | DocumentDB/Mongo client 가능성 | DocumentDB branch 확인 |
| `redis`, `REDIS_URL`, `CACHE_HOST` | ElastiCache Redis client 가능성 | ElastiCache branch 확인 |
| 저장소 관련 문자열 없음 | stateless 또는 외부 API 가능성 | no-store branch로 시작 |
| `/v1/newapp`, `/v2/product` | ALB listener rule 경로 후보 | 실제 health/API 요청으로 확정 |
| `healthcheck`, `/health`, `8080` | probe/Service/TargetGroup 후보 | 실제 컨테이너 기동 로그로 확정 |

문자열은 가설일 뿐이다. 인프라를 바꾸기 전 실제 Pod 로그와 요청 1건으로 확정한다.

## 기본 배포 원칙

새 binary에는 아래가 모두 별도로 필요하다.

```text
ECR repository
Deployment
ClusterIP Service
Target Group
ALB listener rule
TargetGroupBinding
ServiceAccount
HPA
ConfigMap/Secret entries
```

resource name은 binary 이름과 분리한다. 예를 들어 경로가 `/v2/product`여도 Kubernetes Deployment, Service, Target Group 이름을 기존 `product`로 재사용하지 않는다. `newapp` 같은 별도 식별자를 쓴다. 그래야 `/v1/product`가 기존 product Target Group으로 계속 간다.

CloudFront 기본 behavior는 동적 API를 ALB로 넘기고 캐시를 끈 상태다. 새 API는 별도 캐시 요구가 바이너리/과제에 명시되기 전까지 CloudFront cache behavior를 추가하지 않는다.

## 노드 배치 결정표

### A. 처음에는 apps node에 한 replica

새 binary가 DB/cache client여도 저장소가 노드를 차지하는 것은 아니다. 앱 Pod가 쓰는 CPU·메모리와 connection 수가 문제다. 처음에는 아래 조건을 모두 만족할 때만 apps node에 1 replica로 올린다.

```bash
kubectl get nodes -l role=apps
APPS_NODE="$(kubectl get nodes -l role=apps -o jsonpath='{.items[0].metadata.name}')"
kubectl describe node "$APPS_NODE" | sed -n '/Allocatable:/,/System Info:/p'
kubectl top node "$APPS_NODE"
kubectl -n default top pod -l app=user
kubectl -n default top pod -l app=product
kubectl -n default get pod -o wide
```

| 조건 | 배치 |
| --- | --- |
| 새 Pod request + user/product request + system Pod request가 allocatable 아래이고, 실측 CPU/메모리 여유가 있음 | apps node, `replicas: 1`, HPA max는 1부터 |
| 스케줄은 되지만 user/product latency·restart·CPU가 흔들림 | apps 공유 중단. 새 binary 분리 branch 검토 |
| 새 Pod가 Pending | request를 억지로 낮추지 말고, 분리 node group 또는 apps capacity 변경 검토 |
| binary가 CPU-bound, 대용량 처리, 장시간 worker | 처음부터 stress node에 넣지 말고 별도 node group branch로 |

새 binary의 request/limit은 기존 product의 `512m/512Mi`를 복사하지 않는다. binary를 한 번 띄운 뒤 `kubectl top`과 실제 API 요청으로 정한다. 초기값을 잡아야 하면 작은 값으로 시작하되 limit을 request보다 과도하게 크게 잡아 node overcommit을 만들지 않는다.

### B. apps node에서 HPA를 쓸 수 있는 경우

apps node가 1대 고정이므로 HPA는 “Pod 수가 증가해도 같은 노드에 들어갈 수 있을 때”만 쓴다.

```text
HPA max replicas
≤ floor((apps node allocatable - 기존 Pod requests - system Pod requests) / newapp request)
```

이 식을 만족하지 않으면 HPA가 replica를 늘려도 Pending Pod만 생긴다. 이 상태는 새 API뿐 아니라 같은 node의 user/product endpoint에도 영향을 준다.

새 binary가 가벼운 I/O API이고 1 replica로 SLO를 만족하면 HPA는 `min=1`, `max=1`로 둔다. autoscaling이 필요하다는 증거가 생긴 뒤에만 max를 올린다.

### C. 새 node가 필요한 경우

아래 중 하나면 apps 공유를 포기한다.

- 새 API의 1 replica만으로 user/product의 CPU, memory, restart, latency가 흔들림
- 필요 replica 수가 apps node의 남은 request capacity보다 큼
- binary가 CPU-bound이거나 background worker가 누적됨
- 새 DB/cache client의 connection pool이 user/product RDS를 압박함

선택지는 두 개다.

| 방식 | 장점 | 손해/주의 |
| --- | --- | --- |
| apps node를 2대로 고정 | 가장 단순하고 새 API 시작 시 Ready 보장 | 트래픽 구간 평균 3노드. cost ratio 약 1.5 |
| newapp 전용 ASG/node group | user/product와 CPU·메모리 격리 | 새 node group, CA tags, nodeSelector, HPA, SG를 모두 추가해야 함 |

newapp 전용 group을 min=0으로 만들고 새 API의 유일한 replica까지 거기에 보내면 안 된다. 첫 요청 때 Pod가 Pending이고 node boot/join을 기다리므로 초반 availability를 잃는다. min=0은 이미 apps node에서 Ready인 base replica가 있고, 피크용 Pod만 별도 group으로 보낼 때만 쓴다.

base+burst 분리는 마지막 수단이다.

```text
newapp-base: apps node에서 1 replica, 항상 Ready
newapp-burst: newapp node group에서 HPA, 같은 Service selector
```

두 Deployment의 env, image, probe, Service label을 완전히 같게 유지해야 한다. 현장 1시간 안에 검증할 자신이 없으면 이 구조를 새로 만들지 말고 apps node 2대 고정을 택한다. 비용 2점 손실보다 전체 API 붕괴가 더 크다.

### D. Cluster Autoscaler를 새 group에 연결할 때

현재 Cluster Autoscaler는 stress group의 Pending Pod를 보고 늘어나는 흐름으로 맞춰져 있다. newapp group을 추가할 때는 다음이 모두 필요하다.

```text
k8s.io/cluster-autoscaler/enabled=true
k8s.io/cluster-autoscaler/<cluster-name>=owned
k8s.io/cluster-autoscaler/node-template/label/role=newapp
```

newapp Pod에는 같은 `nodeSelector: { role: newapp }`가 필요하다. taint를 줄 경우 Pod toleration도 같이 넣는다. CA 태그만 넣고 HPA를 안 만들면 Pending Pod가 생기지 않아 scale out이 일어나지 않는다.

자동 확장 전 확인:

```bash
kubectl -n default get hpa newapp
kubectl -n default get pods -l app=newapp -w
kubectl -n kube-system logs deploy/cluster-autoscaler --since=10m
kubectl get nodes -L role
```

## 저장소별 branch

### 1. RDS MySQL을 쓰는 binary

먼저 판단할 것: 새 binary가 **기존 RDS를 같이 쓰는지**, 별도 MySQL이 반드시 필요한지다. 현재 과제의 RDS는 user/product 때문에 이미 필수다. 새 binary가 MySQL client라면 원칙은 기존 RDS 재사용이다. 별도 RDS를 만들면 DB 최소 운영 조건과 계정 비용 한도를 동시에 악화시킨다.

필요 환경변수 후보:

```text
MYSQL_HOST / MYSQL_PORT / MYSQL_USER / MYSQL_PASSWORD / MYSQL_DBNAME
DB_HOST / DB_PORT / DB_USER / DB_PASSWORD / DB_NAME
DATABASE_URL
```

조치 순서:

1. strings와 Pod 시작 로그로 정확한 env 이름을 확정한다.
2. `infra/k8s/scripts/deploy.sh`에서 RDS output을 새 binary 전용 ConfigMap/Secret key로 주입한다.
3. 새 table/schema가 binary에 필수일 때만 만든다. user dump의 기존 데이터·테이블은 바꾸지 않는다.
4. query 조건을 확인한 뒤에만 새 table index를 만든다. 인덱스를 추측으로 추가하지 않는다.
5. replica 수보다 connection 수가 먼저 병목이 된다. binary의 pool env가 있으면 낮게 시작한다.

```bash
kubectl -n default logs deploy/newapp --since=10m
RDS_ID="$(aws rds describe-db-instances \
  --query 'DBInstances[?Engine==`mysql`].DBInstanceIdentifier | [0]' --output text)"
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value="$RDS_ID" \
  --statistics Maximum --period 60 --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

현재 RDS parameter group은 `max_connections=200`이다. 새 binary의 replica 수 × pool 상한 + user/product의 실측 connection 수가 200에 가까우면 HPA부터 멈춘다. DB instance class를 올리거나 RDS Proxy를 추가하는 것은 현장 기본 대응이 아니다. RDS MySQL은 `db.t3.micro`, Multi-AZ, gp3 조건을 유지한다.

### 2. DynamoDB를 쓰는 binary

DynamoDB는 Pod CPU·메모리보다 IAM과 key design이 먼저다.

1. binary가 table 이름, region, endpoint를 어떤 env로 읽는지 확인한다.
2. table 하나와 binary가 요구한 key schema만 만든다. GSI는 error/log 또는 binary contract가 필요하다고 확인된 뒤에만 만든다.
3. 새 binary 전용 ServiceAccount/IRSA에 필요한 action만 준다. `dynamodb:*`는 금지한다.
4. private subnet 경로는 DynamoDB Gateway Endpoint를 추가한다. NAT를 거치게 두지 않는다.

기본 billing은 트래픽 규모를 모르는 현장에서는 on-demand가 안전하지만, 과제/지급문서가 provisioned capacity를 명시하면 그 값을 따른다. DynamoDB를 쓴다고 node를 늘리지는 않는다.

### 3. DocumentDB를 쓰는 binary

DocumentDB는 가장 늦게 선택한다. 클러스터·인스턴스·subnet group·SG·TLS·credential을 모두 새로 만들고 비용도 크다. binary가 `mongodb`/`DocumentDB` client임을 실제 시작 로그까지 확인하기 전에는 만들지 않는다.

필수 확인:

```text
endpoint env 이름
port
username/password 또는 connection string
TLS required 여부
CA file path 또는 CA bundle env
database / collection 이름
```

- endpoint는 private subnet에서만 접근시킨다.
- SG는 newapp node/pod 경로에서 DocumentDB port만 허용한다.
- TLS가 필요하면 CA bundle을 image 또는 ConfigMap으로 제공한다. `tls=false` 같은 우회는 하지 않는다.
- DocumentDB는 RDS를 대체하지 않는다. user/product의 MySQL env와 RDS 자원은 그대로 둔다.
- 이 branch는 앱 Pod보다 관리형 DB 비용·생성 시간이 더 큰 리스크다. 현장 시간과 과제 허용성을 먼저 판단한다.

### 4. ElastiCache Redis를 쓰는 binary

Redis는 일반적으로 DB 대체가 아니라 cache/session/queue 용도다. binary가 정말 Redis endpoint 없이는 시작하지 못할 때만 만든다.

필수 확인:

```text
REDIS_HOST / REDIS_PORT / REDIS_URL / CACHE_HOST
TLS 여부
AUTH token 또는 IAM authentication 여부
cluster mode 여부
```

- endpoint와 port는 ConfigMap, AUTH token은 Secret에 넣는다.
- private subnet + newapp security group 경로만 연다.
- 평문 password를 코드나 ConfigMap에 넣지 않는다.
- IAM auth를 쓰는 binary만 전용 IRSA가 필요하다. AUTH token 방식이면 IAM이 아니라 Secret이 핵심이다.
- Redis를 써도 user/product의 RDS connection 문제는 해결되지 않는다. 새 binary의 cache와 기존 product DB 부하를 같은 문제로 보지 않는다.

### 5. 저장소를 안 쓰는 binary

저장소 env, IRSA, SG, 관리형 자원을 추가하지 않는다. 별도 Deployment/Service/Target Group만 만든다. CPU-bound인지 I/O-bound인지만 보고 apps 공유 또는 분리를 결정한다.

## user/product 보호 규칙

새 binary를 넣은 뒤 이 네 가지가 나빠지면 새 binary부터 줄이거나 분리한다.

```bash
kubectl -n default top pod -l app=user
kubectl -n default top pod -l app=product
kubectl -n default get pod -l app=user
kubectl -n default get pod -l app=product
kubectl -n default logs deploy/user --since=10m | tail -50
kubectl -n default logs deploy/product --since=10m | tail -50
```

| 징후 | 의미 | 첫 조치 |
| --- | --- | --- |
| user/product CPU 또는 memory 급증 | apps node 경합 | newapp request/replica 축소 또는 node 분리 |
| user/product readiness 실패·restart | node 또는 RDS 경합 | newapp HPA 중지, DB connection 확인 |
| RDS DatabaseConnections 급증 | 새 binary pool/replica가 DB를 압박 | newapp replica 1로 고정, pool env 하향 |
| ALB target 5xx 증가 | 새 route 또는 공용 node 영향 | newapp route를 먼저 진단, 기존 target group은 건드리지 않음 |
| product image PUT 403/5xx | new binary 배포와 무관하게 WAF/IRSA가 바뀌었을 가능성 | product-s3-put.md 절차로 즉시 회귀 확인 |

새 binary 때문에 기존 user/product의 resource request를 낮추지 않는다. 기존 Pod를 stress node에 옮기지도 않는다. 두 서비스의 SLO는 새 API보다 우선이다.

## 실제 반영 파일 순서

현장에서 binary contract가 확정된 뒤 아래 파일만 건드린다. 모든 파일을 미리 고치지 않는다.

| 순서 | 파일 | 하는 일 |
| --- | --- | --- |
| 1 | `docker/build-push.sh`, `infra/terraform/modules/ecr/main.tf` | 새 binary image build/push와 ECR repository 추가 |
| 2 | `infra/k8s/base/newapp.yaml` | Deployment, Service, probe, request/limit, nodeSelector, ServiceAccount, HPA 작성 |
| 3 | `infra/terraform/modules/alb/main.tf` | 새 Target Group과 실제 route의 listener rule 추가. `/v2/product`는 기존 `/v1/${app}` 생성 규칙에 억지로 끼우지 않음 |
| 4 | `infra/k8s/overlays/prod/targetgroupbindings.yaml.tmpl` | 새 Target Group ARN과 newapp Service 연결 |
| 5 | `infra/k8s/overlays/prod/kustomization.yaml.tmpl` | 새 ECR image와 manifest 추가 |
| 6 | `infra/k8s/scripts/deploy.sh` | binary가 실제로 읽는 ConfigMap/Secret env를 생성 |
| 7 | `infra/terraform/main.tf` | 새 binary 전용 IRSA와, 실제로 확인된 DynamoDB/DocumentDB/ElastiCache만 추가 |
| 8 | `infra/terraform/modules/eks/*` | apps 공유가 실패한 경우에만 newapp node group/CA tag 추가 |

route가 `/v2/product`여도 Target Group/Service 이름은 `newapp`으로 고정해 기존 `product`와 분리한다. ALB가 path로 구분하므로 이름을 맞출 이유가 없다.

## 새 API 배포 전 통과선

```text
binary의 route, port, healthcheck 확인
newapp Deployment/Service/Target Group/TargetGroupBinding이 기존 product와 별개
newapp ServiceAccount가 기존 product-sa와 별개
저장소 env와 IAM/Secret/SG가 실제 client contract와 일치
newapp healthcheck 200
저장소 read/write 1회 성공
user/product/stress가 모두 Ready
user/product RDS connection 및 Pod restart 증가 없음
newapp Pod request가 선택한 node의 allocatable 범위 안
HPA max가 실제 배치 가능한 replica 수를 넘지 않음
```

위 조건을 넘긴 뒤에만 newapp의 HPA max 또는 전용 node group을 늘린다. 추가 binary가 있다는 사실만으로 노드나 저장소를 더 만들지 않는다.
