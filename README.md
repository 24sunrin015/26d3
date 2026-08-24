# Worldskills Korea Nat'l Competition Day3 - System Operation
아자아자 열심히 고득점해서 금메달따자!

## 3과제 issues
1. 

## Infra apply 전 할 일
1. provided/ 디렉토리에 지급파일 배치. 이름 가능하면 똑같게.
2. infra/terraform/rds/tables/*.sql 파일들 현장 지급파일이랑 똑같이 맞추거나, 없애기.
3. (바이너리 확인) ./product --help로 S3 bucket env key 확인해서 configmap 수정해서 반영하기
4. (바이너리 확인) product binary가 s3 어떤 path에 image upload 하는지 보고, cf s3 경로 조절하기.

## 현장에서 풀이 순서
모든건 Makefile로 작업 가능. 그니까 뭔 일 없으면 걍 make cmd ㄱㄱ.
1. `export STUDENT_ID=<비번호>`로 비번호 설정.
2. `make apply` — 인프라 전체(VPC/EKS/RDS/S3/ECR/ALB/WAF/CloudFront/monitoring) + 클러스터 애드온(LB Controller·Cluster Autoscaler·metrics-server, helm_release로 apply 때 같이 설치됨).
3. `make images` — provided/ 바이너리를 S3에 올려 CodeBuild가 빌드 → ECR 푸시(로컬 Docker 불필요).
4. `make deploy` — 앱 배포(kubectl apply -k). TargetGroupBinding으로 ALB 연결.
5. `make db-seed ARGS="--user-dump=provided/load_user.dump"` — 덤프를 RDS에 적재(+ 커버링 인덱스 복구·ANALYZE). apply 때 자동 적재 안 함. product 덤프도 있으면 `--product-dump=provided/<파일>` 추가. 준 것만 적재하고, 안 주면 그 테이블은 안 건드림(덤프 없으면 생략).
6. (opt) `make upload-images` — 제공 이미지 S3 업로드. 만약 pre 제공이미지 없다면 업로드 진행 X
7. `make endpoint` — 채점 플랫폼에 제출할 단일 엔드포인트 출력.

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
