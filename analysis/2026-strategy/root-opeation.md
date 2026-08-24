# root operation: 노드 증설 · 통합 · 비용 대응표

이 문서는 경기 중 새 API 추가, Pod scale-out, node 2대 이상 상태에서 보는 운영표다. 목표는 user/product/stress를 살린 채 **필요할 때만 노드를 늘리고, 여유가 생기면 다시 2노드 baseline으로 돌아오는 것**이다.

## 먼저 구분: apps node와 stress node

```text
apps node group   user / product / newapp
stress node group stress 전용, dedicated=stress:NoSchedule
```

stress node는 apps node와 통합 대상이 아니다. stress Pod는 `role=stress`와 toleration을 요구하고, user/product/newapp은 stress taint를 tolerate하지 않는다. node 수가 2일 때는 apps 1대 + stress 1대가 최소 정상 구성이다.

비우려는 node가 어느 group인지 먼저 확인한다.

```bash
kubectl get nodes -L role
kubectl get pods -A -o wide
kubectl get hpa -A
```

| 비우려는 node | 가능 여부 | 이유 |
| --- | --- | --- |
| scale-out으로 추가된 apps node | 조건부 가능 | apps Pod가 node 1에 다시 들어가면 CA가 drain 가능 |
| apps의 유일한 node | 불가 | user/product/newapp의 기본 배치가 사라짐 |
| stress node | 기본적으로 불가 | stress Pod가 apps node로 이동할 수 없음 |
| stopped warm pool instance | 조치 불필요 | Ready node도 running EC2도 아니므로 비용 ratio에 안 잡힘 |

## 추가 API가 생길 때 권장 구조

현재 apps node group은 `min=max=desired=1`이다. 새 API 때문에 node 2가 필요해진다면 단순히 `apps_node_count=2`로 고정하지 않는다. 그러면 부하가 끝나도 apps node 2대가 계속 살아 비용 ratio가 올라간다.

권장값은 아래다.

```text
apps node group: min=1, desired=1, max=2
Cluster Autoscaler discovery tags: 추가
user/product/newapp: nodeSelector role=apps
```

동작은 이렇다.

```text
1. apps node 1대에서 user/product/newapp 기본 replica 실행
2. HPA가 replica를 늘림
3. 새 Pod가 request 부족으로 Pending
4. Cluster Autoscaler가 apps node 2를 생성
5. 부하 감소 → HPA scale down
6. node 1에 모든 movable Pod가 다시 들어감
7. Cluster Autoscaler가 node 2를 drain하고 ASG를 1대로 축소
```

현재 CA 설정의 `scale-down-unneeded-time=2m`, `scale-down-delay-after-add=2m`은 node 2를 급하게 지우지 않도록 한다. 이 흐름을 쓰려면 apps node group에도 CA discovery tag와 `role=apps` node-template label을 추가해야 한다.

## node 2를 비울 수 있는 조건

Kubernetes는 비어 있는 node를 보고 평상시에 Pod를 다른 node로 옮기지 않는다. Cluster Autoscaler가 scale-down 후보로 판단하면 node 2를 cordon하고 drain하면서, **모든 Pod가 node 1에 재스케줄 가능한지** 확인한다.

node 2를 지울 수 있는 조건은 모두 참이어야 한다.

```text
node 1 allocatable request capacity에 node 2의 앱 Pod requests까지 합쳐서 들어감
Pod가 node 1의 label/taint/affinity 조건을 만족함
PodDisruptionBudget이 eviction을 허용함
Pod가 local data를 잃어도 됨
해당 node group의 min size보다 현재 desired가 큼
```

실측은 request 기준으로 한다. CPU 실사용이 낮아도 request가 node 1에 안 들어가면 이동하지 못한다.

```bash
NODE1="<남길 apps node>"
NODE2="<비울 apps node>"

kubectl describe node "$NODE1" | sed -n '/Allocatable:/,/System Info:/p'
kubectl describe node "$NODE1" | sed -n '/Allocated resources:/,/Events:/p'
kubectl get pods -A -o wide --field-selector "spec.nodeName=$NODE2"
kubectl get pdb -A
kubectl top node "$NODE1"
kubectl top node "$NODE2"
```

### 현재 apdev-eks 기준 예시

apps node 1의 allocatable CPU는 1930m, 현재 request는 1474m다. 남은 CPU request는 456m다.

| node 2에 남은 apps Pod | node 1 통합 가능성 |
| --- | --- |
| newapp request 250m, 다른 scale-out Pod 없음 | 가능. 합계 1724m |
| newapp replica 2개가 각각 250m | 불가. 합계 1974m |
| newapp request 512m 1개 | 불가. 합계 1986m |
| user/product HPA replica가 추가됨 | 각 Pod request를 더해 다시 계산 |

이 계산을 통과하지 못하면 node 2는 정상적인 비용이다. 억지로 drain하면 Pod가 Pending이 되거나 user/product가 흔들린다.

## 자동 통합이 안 되는 이유별 조치

| 증상 | 확인 | 조치 |
| --- | --- | --- |
| node 2가 2분 넘게 남음 | `kubectl -n kube-system logs deploy/cluster-autoscaler --since=10m` | CA reason 확인. request가 안 맞으면 HPA/Pod 수부터 줄임 |
| node 2 Pod가 node 1에 안 들어감 | node 1 Allocated resources | request를 실제 필요치보다 낮추지 말고 node 2 유지 또는 app 구조 조정 |
| CA가 apps ASG를 발견 못 함 | CA log에 `No expansion options` | apps ASG discovery tag, node-template label 확인 |
| Pod에 role/taint/affinity 제약 | `kubectl get pod <pod> -o yaml` | apps Pod가 `role=apps`에 재배치 가능한지 수정 |
| PDB가 drain 막음 | `kubectl get pdb -A` | replica를 먼저 늘리거나 PDB를 조정. PDB 강제 삭제 금지 |
| `emptyDir` 또는 local state 사용 | Pod spec, binary 동작 | 상태를 잃어도 되는지 확인 전 drain 금지 |
| DaemonSet만 node 2에 남음 | `kubectl get pods -A -o wide` | 정상. CA/drain에서 DaemonSet은 eviction 대상이 아님 |

## 수동으로 node 2를 비워야 할 때

자동 통합을 기다리는 것이 우선이다. 수동 drain은 CA가 멈췄거나, node 2를 즉시 회수해야 하는데 아래 조건을 이미 확인했을 때만 쓴다.

### drain 전

```bash
NODE2="<비울 apps node>"

kubectl get pods -A -o wide --field-selector "spec.nodeName=$NODE2"
kubectl get pdb -A
kubectl get deploy -n default user product newapp
kubectl get pods -n default -l app=user
kubectl get pods -n default -l app=product
kubectl get pods -n default -l app=newapp
```

다음 중 하나라도 참이면 drain하지 않는다.

- user, product, newapp 중 해당 node에만 Ready replica가 있음
- destination node request capacity가 부족함
- binary가 local disk에 상태를 저장함
- node가 stress group임
- 현재 외부 트래픽에서 5xx, readiness 실패, RDS connection 급증이 보임

single replica를 drain해야 한다면 먼저 destination node에 같은 workload의 두 번째 Ready replica를 만든다. 단, 그 replica가 node 1에 실제로 들어갈 capacity가 있을 때만 한다. PDB `minAvailable: 1`은 replica 1개인 Deployment의 drain을 막는 정상 동작이다.

### cordon → drain

```bash
kubectl cordon "$NODE2"

kubectl drain "$NODE2" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --timeout=5m
```

- `cordon`은 새 Pod 배치만 막는다. 기존 Pod는 그대로다.
- `drain`은 PodDisruptionBudget과 graceful termination을 존중하며 eviction한다.
- DaemonSet Pod는 남는 것이 정상이다.
- `--delete-emptydir-data`는 emptyDir 데이터를 삭제한다. 새 binary가 local cache를 재생성 가능한 경우에만 사용한다.
- `--force`는 controller가 없는 Pod까지 지울 수 있으므로 기본 명령에 넣지 않는다.

drain이 실패하면 메시지를 그대로 보고 원인을 해결한다. PDB, request capacity, local state 문제를 무시하고 강제로 진행하지 않는다.

### drain 후

```bash
kubectl get pods -A -o wide
kubectl get nodes -L role
kubectl -n default rollout status deploy/user --timeout=180s
kubectl -n default rollout status deploy/product --timeout=180s
kubectl -n default rollout status deploy/newapp --timeout=180s
kubectl get hpa -A
```

user/product/newapp이 모두 Ready이고 node 2에 DaemonSet 외 일반 Pod가 없으면 ASG/CA가 node를 줄일 수 있다. node가 계속 남으면 ASG desired/min과 CA log를 확인한다. 수동으로 EC2 instance를 terminate하지 않는다. ASG state와 Terraform state가 어긋난다.

## HPA 운영 기준

HPA는 CPU가 높다고 무조건 늘리는 장치가 아니다. apps node group의 request capacity와 CA가 함께 준비돼야 한다.

| 상황 | HPA 설정 |
| --- | --- |
| newapp 1개가 node 1에 충분히 들어가고 성능도 안정 | min=1, max=1 |
| replica 2개가 node 1에 모두 들어감 | min=1, max=2 가능. node 증설 없음 |
| replica 2개째부터 Pending이 되고 apps ASG가 CA 대상 | min=1, max=2. HPA→Pending→CA로 node 2 생성 |
| 새 binary가 CPU-bound/worker 누적 | HPA target을 실부하에서 잡고, user/product와 분리 여부 먼저 판단 |
| DB connection이 병목 | HPA max부터 낮춤. node 증설이 DB connection 문제를 해결하지 않음 |

newapp HPA가 scale down된 뒤에는 node 2를 바로 수동 삭제하지 않는다. background work, connection close, target deregistration이 끝나고 CA의 2분 판단을 기다린다.

## 전체 운영 체크

### 1. 30초마다 볼 것

```bash
watch -n 30 'kubectl get nodes -L role; echo; kubectl get hpa -A; echo; kubectl -n default get pods -o wide'
```

### 2. 부하가 튀면 볼 것

```bash
kubectl top nodes
kubectl -n default top pods
kubectl -n kube-system logs deploy/cluster-autoscaler --since=5m | tail -100
```

### 3. 점수 방어 우선순위

1. user/product/stress의 2xx와 SLO를 먼저 지킨다.
2. 새 API는 replica/HPA를 줄여 기존 API 경합을 막는다.
3. stress node는 독립 유지한다.
4. 부하가 빠진 뒤 CA가 apps node 2를 통합하도록 둔다.
5. 평균 node 수를 보고 비용 점수를 회복한다.

## 금지

```text
stress node를 drain해서 apps Pod를 옮기기
request가 안 맞는데 Pod request만 허위로 낮추기
Ready replica 1개인 user/product를 확인 없이 drain하기
PDB를 지우거나 drain에 --force를 붙여 강제 eviction하기
ASG/EC2를 콘솔이나 CLI로 직접 terminate하기
apps node를 2대로 고정한 뒤 부하가 끝나도 그대로 두기
```

node 2를 비우는 최선의 방법은 “node 1에 다시 들어갈 수 있도록 HPA replica와 request를 정상 범위로 낮추고, CA가 drain하게 두는 것”이다. 수동 drain은 그 자동 경로가 막혔을 때만 쓴다.
