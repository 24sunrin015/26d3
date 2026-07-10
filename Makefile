INFRA_DIR   := infra/terraform
K8S_OVERLAY := infra/k8s/overlays/prod
PROVIDED    := provided
BINARIES    := user product stress

export TF_VAR_student_id := $(STUDENT_ID)

.PHONY: check-id check-bin up down init plan apply destroy fmt validate \
        images deploy k8s k8s-down endpoint upload-images

# ── 이중 blocker (현장 사고 방지) ─────────────────────────────
check-id:
ifndef STUDENT_ID
	$(error STUDENT_ID가 설정되지 않았습니다. 'export STUDENT_ID=<비번호>' 후 다시 실행하세요)
endif
	@test -n "$(STUDENT_ID)" || { echo "STUDENT_ID가 비어 있습니다"; exit 1; }
	@echo "STUDENT_ID=$(STUDENT_ID)"

check-bin:
	@missing=""; for b in $(BINARIES); do \
		test -f "$(PROVIDED)/$$b" || missing="$$missing $$b"; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "provided/ 에 앱 바이너리가 없습니다:$$missing"; \
		echo "훈련: task3-author에서 'make publish', 현장: 지급 바이너리를 provided/ 에 넣으세요"; \
		exit 1; \
	fi; \
	echo "binaries OK: $(BINARIES)"

# ── 전체 플로우 ──────────────────────────────────────────────
# apply(인프라 + 애드온 helm_release) → images(ECR 푸시) → deploy(앱)
up: check-id check-bin init apply images deploy endpoint

down: check-id
	terraform -chdir=$(INFRA_DIR) destroy -auto-approve

# ── Terraform ────────────────────────────────────────────────
init: check-id
	terraform -chdir=$(INFRA_DIR) init

plan: check-id
	terraform -chdir=$(INFRA_DIR) plan

apply: check-id
	terraform -chdir=$(INFRA_DIR) apply -auto-approve

destroy: check-id
	terraform -chdir=$(INFRA_DIR) destroy -auto-approve

fmt:
	terraform -chdir=$(INFRA_DIR) fmt -recursive

validate:
	terraform -chdir=$(INFRA_DIR) validate

# ── 이미지 & 배포 ────────────────────────────────────────────
images: check-bin
	bash docker/build-push.sh

deploy: check-id check-bin
	bash infra/k8s/scripts/deploy.sh

# k8s = 앱 배포 (컨트롤러는 terraform apply의 helm_release로 이미 설치됨)
k8s: deploy

k8s-down: check-id
	kubectl delete -k $(K8S_OVERLAY) --ignore-not-found || true

# 제공 이미지 대량 업로드 (S3). 소스 기본값 provided/images
upload-images: check-id
	bash scripts/upload_images.sh

# 제출용 단일 엔드포인트 출력
endpoint:
	@echo "── 제출 엔드포인트 ──"
	@terraform -chdir=$(INFRA_DIR) output -raw endpoint; echo
