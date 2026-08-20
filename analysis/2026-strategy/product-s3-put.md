# product 바이너리 현장 분석 · 인프라 조치표

지급 product 바이너리를 받은 직후부터 트래픽 시작 전까지 보는 문서다. 목적은 하나다. **바이너리가 기대하는 S3 계약을 확인하고, 그 결과에 맞춰 k8s·CloudFront·WAF를 고친 뒤 이미지 PUT/GET을 실제로 통과시키는 것.**

훈련용 바이너리의 구현은 참고만 한다. 현장 바이너리 관찰 결과가 다르면 현장 결과를 따른다.

## 0~10분: 바이너리 계약 먼저 뽑기

```bash
file provided/product
sha256sum provided/product
chmod +x provided/product

strings -a provided/product | rg -i \
  'S3_BUCKET|BUCKET|AWS_REGION|image_path|PutObject|multipart|FormFile|/images|/v1/product'
```

아래를 메모한다.

| 확인할 것 | 확인 방법 | 인프라 조치 위치 |
| --- | --- | --- |
| S3 버킷 환경변수명 | `strings` 결과 | `infra/k8s/scripts/deploy.sh`의 `config.env` |
| 리전 환경변수명 | `strings` 결과 | 같은 파일의 `AWS_REGION`, `AWS_DEFAULT_REGION` |
| 이미지 form field 이름 | `FormFile`, `image`, `file` 문자열 | PUT 검증 curl과 현장 테스트 |
| S3 key prefix | `images/`, `uploads/`, `product/` 문자열 및 뒤의 실제 PUT | CloudFront `/images` prefix function |
| 이미지 경로 응답 필드 | `image_path`, `path`, `key` 문자열 및 실제 PUT 응답 | 이후 GET URL 조립 방식 |

`S3_BUCKET`가 아니면 deploy script가 만든 `config.env`에 실제 이름을 추가한다. 변수 이름을 추측해 바꾸지 않는다.

## 10~45분: 인프라 반영

```bash
export STUDENT_ID=<비번호>
make apply
make images
make deploy
make endpoint

export ENDPOINT="$(make -s endpoint | tail -1)"
export BUCKET="$(terraform -chdir=infra/terraform output -raw s3_bucket)"
```

여기까지는 기존 흐름대로 간다. product image를 올리기 전에는 S3 key, cache TTL, WAF rule을 확정하지 않는다.

## 45~60분: 실제 PUT으로 계약 확정

먼저 product id를 만든다. 이미 덤프에 있는 id를 써도 된다.

```bash
export PRODUCT_ID="image-check-$(date +%s)"
export UUID_1="$(uuidgen | tr '[:upper:]' '[:lower:]')"
export UUID_2="$(uuidgen | tr '[:upper:]' '[:lower:]')"
export IMAGE_1="provided/images/<첫 파일>.jpg"
export IMAGE_2="provided/images/<다른 파일>.jpg"

curl -sS -i -X POST "$ENDPOINT/v1/product" \
  -H 'Content-Type: application/json' \
  -d "{\"requestid\":\"image-create\",\"uuid\":\"$UUID_1\",\"id\":\"$PRODUCT_ID\",\"name\":\"$PRODUCT_ID\",\"price\":1234}"
```

아래 PUT은 훈련용 계약이다. `image` field가 아니거나 `id` 위치가 다르면 0~10분에 확인한 바이너리 문자열과 응답을 보고 그 한 줄만 바꾼다.

```bash
curl -sS -X PUT "$ENDPOINT/v1/product" \
  -F "id=$PRODUCT_ID" \
  -F 'requestid=image-put-1' \
  -F "uuid=$UUID_1" \
  -F "image=@$IMAGE_1" | tee /tmp/product-put-1.json

KEY_1="$(jq -r '.image_path // empty' /tmp/product-put-1.json)"
printf 'KEY_1=%s\n' "$KEY_1"
```

### 여기서 확정할 네 가지

| 관찰 결과 | 의미 | 즉시 조치 |
| --- | --- | --- |
| PUT `200`, `image_path` 존재 | 앱→S3→RDS 기본 흐름 통과 | 다음 GET 확인으로 진행 |
| `S3_BUCKET not set` | env 이름 또는 주입 누락 | deploy script의 `config.env`에 실제 env 이름 추가 후 `make deploy` |
| `AccessDenied`, `PutObject` 실패 | IRSA/bucket 권한 문제 | `product-sa` IRSA와 app S3 policy 확인 후 재배포 |
| `400 image file required` | form file field 이름이 다름 | 현장 바이너리 계약에 맞춰 curl/분석 메모 수정 |
| `400 id required` | id form/query 위치가 다름 | id 위치를 바꿔 재시도 |
| `403` | WAF가 정상 multipart PUT을 차단 | 아래 WAF 조치 |
| `500`, `504`, timeout | S3/RDS 연결 또는 파일 크기 문제 | 아래 PUT 장애 조치 |

## S3 key와 CloudFront 경로 맞추기

```bash
aws s3api head-object --bucket "$BUCKET" --key "$KEY_1"
curl -i "$ENDPOINT/images/$KEY_1"
```

| 결과 | 원인 판단 | 조치 파일 |
| --- | --- | --- |
| 둘 다 성공 | key와 `/images` 변환이 맞음 | 변경 없음 |
| S3 object 없음 | 앱이 다른 버킷/key로 저장하거나 PUT은 실제 실패 | `config.env`, IRSA, product 로그 확인 |
| S3 object는 있는데 CloudFront 404 | S3 key prefix와 CloudFront function 불일치 | `infra/terraform/modules/cloudfront/main.tf` |
| S3 object는 있는데 CloudFront 403 | OAC bucket policy 또는 distribution 연결 문제 | 같은 CloudFront module |

현재 CloudFront function은 `/images/foo.jpg`를 S3 key `foo.jpg`로 바꾼다.

| 실제 S3 key | CloudFront function 조치 |
| --- | --- |
| `foo.jpg` | 현재 설정 유지 |
| `images/foo.jpg` | prefix 제거 function을 제거하거나 `images/`를 보존 |
| `uploads/foo.jpg` | `/images/`를 `uploads/`로 바꾸는 rewrite 적용 |
| `product/foo.jpg` | `/images/`를 `product/`로 바꾸는 rewrite 적용 |

수정 후에는 `make apply`만 다시 실행하고, 같은 PUT→head-object→GET을 반복한다.

## 캐시 판단: 반드시 두 번째 PUT까지 확인

```bash
curl -sS -X PUT "$ENDPOINT/v1/product" \
  -F "id=$PRODUCT_ID" \
  -F 'requestid=image-put-2' \
  -F "uuid=$UUID_2" \
  -F "image=@$IMAGE_2" | tee /tmp/product-put-2.json

KEY_2="$(jq -r '.image_path // empty' /tmp/product-put-2.json)"
printf 'KEY_1=%s\nKEY_2=%s\n' "$KEY_1" "$KEY_2"

curl -sS "$ENDPOINT/v1/product?id=$PRODUCT_ID&requestid=image-get&uuid=$UUID_2" | jq .
curl -sS -o /tmp/image-2.out "$ENDPOINT/images/$KEY_2"
shasum -a 256 "$IMAGE_2" /tmp/image-2.out
```

| 결과 | 판단 | 조치 |
| --- | --- | --- |
| `KEY_1 != KEY_2`, 새 파일 hash 일치 | versioned key | long TTL 유지. invalidation 하지 않음 |
| `KEY_1 == KEY_2`, 새 파일 hash 일치 | overwrite형이지만 이번 edge에 stale 없음 | short TTL 적용 후 다시 확인 |
| `KEY_1 == KEY_2`, 이전 hash | stale image | short TTL 적용 후 재시험 |
| product GET의 `image_path != KEY_2` | DB 갱신 실패 또는 응답 계약 차이 | product 로그와 DB 확인 |

versioned key는 URL 자체가 바뀌므로 CloudFront invalidation이 필요 없다. 훈련용 앱은 `<id>-<UnixNano>.<ext>` 새 key를 만든다. 현장 바이너리도 이 동작이면 현재 `/images/*` 장기 캐시를 유지한다.

overwrite형일 때만 `/images/*` cache policy를 아래로 낮춘다.

```text
min TTL     0초
default TTL 5초
max TTL     30초
```

PUT마다 invalidation을 호출하지 않는다. distribution ID, CloudFront IAM 권한, 전파 대기 시간이 추가돼 현장 리스크만 커진다.

## 정상 PUT이 403일 때

```bash
WAF_LOG_GROUP="$(aws logs describe-log-groups \
  --log-group-name-prefix 'aws-waf-logs-' \
  --query 'logGroups[0].logGroupName' --output text)"
aws logs tail "$WAF_LOG_GROUP" --since 10m --follow
```

| WAF 로그 | 조치 |
| --- | --- |
| CommonRuleSet의 body rule | `PUT /v1/product` multipart body 검사 rule만 Count override |
| `BlockedUserAgents` | 현장 정상 요청 UA가 걸린 정규식만 제거 |
| 다른 managed rule | 해당 rule 이름을 기록하고 PUT 경로에만 scope-down 또는 override 검토 |

Web ACL 전체를 Count로 바꾸지 않는다. 미제공 경로는 404, 제공 API의 비정상 요청은 403이라는 채점 조건을 유지해야 한다.

## PUT이 500/timeout일 때

```bash
kubectl -n default get pod -l app=product -o wide
kubectl -n default logs deploy/product --since=10m
kubectl -n default top pod -l app=product
kubectl -n default get events --sort-by=.lastTimestamp | tail -30
```

| 상태 | 조치 |
| --- | --- |
| `AccessDenied` | product ServiceAccount의 IRSA role ARN, `s3:PutObject` policy, bucket 이름 확인 |
| `s3 upload failed` | `AWS_REGION`, S3 gateway endpoint, bucket name 확인 |
| `DB update failed` | RDS address/secret 및 product id 존재 확인 |
| OOMKilled | 지급 이미지 크기 확인 후 product Pod memory만 필요한 만큼 상향 |
| 첫 GET만 느림, 이후 200 | 정상 cache miss. 조치 없음 |

훈련 corpus는 평균 약 5.9KB, 최대 약 6.6KB다. 현장 이미지는 더 클 수 있으므로 작은 파일 하나와 가장 큰 파일 하나만 PUT해 본다. 대량 이미지 업로드나 반복 PUT으로 성능을 망가뜨리지 않는다.

## 제출 전 마지막 줄

```text
PUT 200
PUT 응답 image_path 존재
S3 head-object 성공
GET /images/<image_path> 200
같은 product의 두 PUT에서 key 규칙 확인
product GET이 마지막 image_path 반환
정상 multipart PUT WAF block 0
```

여기까지 통과하면 image 경로를 신경 쓰지 말고 나머지 서비스와 노드 운영으로 넘어간다.
