# Worldskills Korea Nat'l Competition Day3 - System Operation
아자아자 열심히 고득점해서 금메달따자!

## 3과제 issues
1. 

## 바이너리 분석 체크

지급 직후 user와 product 바이너리를 `analysis.serve.cx`으로 분석해 둔다. 아래는 apply 전에 확인한다.

- product가 읽는 S3 bucket 환경변수 이름
- 이미지 object key의 prefix와 CloudFront `/images/*` 경로 정합성
- 이미지 수정(PUT) 때 기존 object를 덮어쓰는지, 새 object를 만드는지
- 이미지 업로드 형식과 대략적인 요청 크기
- user/product GET에 요청별 sleep 또는 반복되는 tail latency가 있는지

분석 결과에 따라 `config.env` 생성값, S3/CloudFront 경로, `EXTRA_APPS`, DB dump 파일을 맞춘다. dump가 없거나 테이블 정의가 달라지면 `infra/terraform/rds/tables/*.sql`도 지급물 기준으로 고치거나 제거한다.

GET에 독립적인 sleep이나 tail latency가 확인되면 hedger를 유지한다. 그런 지연이 없고 짧은 부하 확인에서도 GET이 안정적으로 0.2초 안에 끝나면 hedger는 이득이 없으므로 끈다.

```bash
HEDGE_ENABLED=false make apply
HEDGE_ENABLED=false make images
HEDGE_ENABLED=false make deploy
```

`HEDGE_ENABLED=false`면 hedger ECR·ALB target group·GET listener rule·Kubernetes Deployment/Service/TargetGroupBinding을 만들지 않으며, user/product GET은 각 앱 target group으로 바로 간다. 기본값은 `true`다.

## 현장에서 풀이 순서
1. `provided/`에 user, product, stress 바이너리와 dump·이미지 지급물을 넣는다.
2. user/product 분석을 시작하고, 위 체크 항목에 맞춰 IaC와 지급물을 조정한다. 추가 서비스가 있으면 `EXTRA_APPS`도 이 단계에서 설정한다.
3. 작업 환경을 정한다. PowerShell만으로는 Makefile과 Bash 스크립트를 실행할 수 없으므로 Windows에서는 WSL 또는 Git Bash를 쓴다. 앱과 hedger 이미지는 CodeBuild가 빌드하므로 로컬 Go·Docker는 필요 없다.
4. `export STUDENT_ID=<비번호>`로 비번호를 설정한다.
5. `make apply` — VPC/EKS/RDS/S3/ECR/ALB/WAF/CloudFront와 클러스터 애드온을 반영한다.
6. `make images` — 지급 바이너리와 hedger를 CodeBuild로 빌드해 ECR에 push한다.
7. `make deploy` — Kubernetes 앱과 TargetGroupBinding을 적용한다.
8. `make db-seed ARGS="--user-dump=provided/load_user.dump"` — dump를 RDS에 적재한다. product dump도 있으면 `--product-dump=provided/<파일>`을 추가하고, 없으면 생략한다.
9. 제공 이미지가 있으면 `make upload-images`를 실행한다.
10. `make endpoint`로 채점 플랫폼에 제출할 주소를 확인한다.

```bash
export STUDENT_ID=<비번호>   # 안 하면 모든 make가 막힘

make apply
make images
make deploy
make db-seed ARGS="--user-dump=provided/load_user.dump"   # product 있으면 --product-dump=... 추가, 없으면 생략 가능
make upload-images
make endpoint

make down        # 전체 철거 (terraform destroy)
```

## 추가 바이너리 대응

추가 Go 바이너리가 나오지 않으면 `EXTRA_APPS`를 설정하지 않는다. 기존 순서 그대로 진행하면 된다.

추가 바이너리 `orders`가 나오고 API 경로가 `/v1/orders`라면:

```bash
cp <지급경로>/orders provided/orders
export EXTRA_APPS=orders

make apply     # apdev-orders ECR, ALB /v1/orders, target group 생성
make images    # provided/orders 빌드·ECR push
make deploy    # orders Deployment, Service, TargetGroupBinding 적용
```

여러 개면 이름을 쉼표로 연결한다.

```bash
export EXTRA_APPS=orders,payment
```

이름은 소문자·숫자·하이픈만 쓸 수 있고 23자 이하여야 한다. 추가 바이너리는 TCP/8080과 `/healthcheck`를 제공해야 한다.

## 동작 확인용 curl 예시

```bash
export CF_DOMAIN=$(make endpoint | tail -1)   # 또는 make endpoint 출력값을 직접 export

curl -i "$CF_DOMAIN/healthcheck"

curl -i "$CF_DOMAIN/v1/user" \
  -X POST -H 'Content-Type: application/json' \
  -d '{"username":"tester","email":"tester@example.com"}'

curl -i "$CF_DOMAIN/v1/product?id=1"

RANDOM_IMAGE=$(aws s3 ls "s3://$(terraform -chdir=infra/terraform output -raw s3_bucket)/" \
  --recursive | awk '{print $NF}' | shuf -n 1)
curl -I "$CF_DOMAIN/images/$RANDOM_IMAGE"

curl -i "$CF_DOMAIN/v1/none"          # 미제공 경로 → 404 기대
curl -i "$CF_DOMAIN/v1/user' OR '1'='1"  # 비정상 요청 → WAF 403 기대
```

## 안전장치 (현장 사고 방지)

- STUDENT_ID 미설정 시 모든 `make` 즉시 중단.
- provided/ 바이너리 누락 시 `make apply/images/deploy` 중단.
- 비번호 SSOT는 `STUDENT_ID` 하나(terraform엔 `TF_VAR_student_id`, k8s엔 `config.env`로 전파).

## for AI
- AI Agent가 README.md에 사용자 지시 없이 작성하는 것은 금지되며, 명시적으로 요청했다 하더라도 재확인하여야 한다.  
- AI Agent는 README.md 대신 AI.RM.md 파일에 작성하여야 한다. 파일이 없을 경우 새로 생성하여 작성하도록 한다.
