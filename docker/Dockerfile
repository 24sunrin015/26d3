# provided/ 바이너리 → 컨테이너 이미지.
# 바이너리는 AL2023 x86_64에서 빌드됨 → 동일 베이스로 호환성 보장.
# CA 인증서(S3 HTTPS), tzdata(KST) 포함.
# Docker Hub 익명 pull 레이트리밋 회피(CodeBuild 등 CI 환경에서 안전) — 동일 이미지, ECR Public Gallery 경유
FROM public.ecr.aws/amazonlinux/amazonlinux:2023

ARG APP
RUN dnf install -y ca-certificates tzdata && dnf clean all
ENV TZ=Asia/Seoul

WORKDIR /app
COPY provided/${APP} /app/app
RUN chmod +x /app/app

EXPOSE 8080
ENTRYPOINT ["/app/app"]
