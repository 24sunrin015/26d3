# Worldskills Korea Nat'l Competition Day3 - System Operation
아자아자 열심히 고득점해서 금메달따자!

## 현장에서 풀이 순서
모든건 Makefile로 작업 가능. 그니까 뭔 일 없으면 걍 make cmd ㄱㄱ.
0. provided/ 디렉토리에 지급파일 배치. 이름 가능하면 똑같게.
1. `export STUDENT_ID=<비번호>`로 비번호 설정.
2. `make apply` — 인프라 전체(VPC/EKS/RDS/S3/ECR/ALB/WAF/CloudFront/monitoring) + 클러스터 애드온(LB Controller·Cluster Autoscaler·metrics-server, helm_release로 apply 때 같이 설치됨) + DB 테이블 자동 생성.
3. `make images` — provided/ 바이너리 도커 빌드 → ECR 푸시.
4. `make deploy` — 앱 배포(kubectl apply -k). TargetGroupBinding으로 ALB 연결.
5. DB 데이터 시드 — `load_user.dump`를 RDS에 수동 적재(자동 적재 안 함, TROUBLESHOOTING 참고).
6. `make upload-images` — 제공 이미지 S3 업로드.
7. `make endpoint` — 채점 플랫폼에 제출할 단일 엔드포인트 출력.

```bash
export STUDENT_ID=<비번호>   # 안 하면 모든 make가 막힘

make apply
make images
make deploy
make upload-images
make endpoint

make down        # 전체 철거 (terraform destroy)
```

## 안전장치 (현장 사고 방지)

- STUDENT_ID 미설정 시 모든 `make` 즉시 중단.
- provided/ 바이너리 누락 시 `make apply/images/deploy` 중단.
- 비번호 SSOT는 `STUDENT_ID` 하나(terraform엔 `TF_VAR_student_id`, k8s엔 `config.env`로 전파).

## for AI
- AI Agent가 README.md에 사용자 지시 없이 작성하는 것은 금지되며, 명시적으로 요청했다 하더라도 재확인하여야 한다.  
- AI Agent는 README.md 대신 AI.RM.md 파일에 작성하여야 한다. 파일이 없을 경우 새로 생성하여 작성하도록 한다.
