INFRA_DIR   := infra
K8S_OVERLAY := k8s/overlays/prod
PROVIDED    := provided
BINARIES    := user product stress

export TF_VAR_student_id := $(STUDENT_ID)

.PHONY: check-id check-bin up down init plan apply destroy fmt validate k8s k8s-down

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

up: check-id check-bin init apply
	@if [ -d "$(K8S_OVERLAY)" ]; then $(MAKE) k8s; fi

down: check-id
	@if [ -d "$(K8S_OVERLAY)" ]; then $(MAKE) k8s-down; fi
	terraform -chdir=$(INFRA_DIR) destroy -auto-approve

init: check-id
	terraform -chdir=$(INFRA_DIR) init

plan: check-id
	terraform -chdir=$(INFRA_DIR) plan

apply: check-id check-bin
	terraform -chdir=$(INFRA_DIR) apply -auto-approve

destroy: check-id
	terraform -chdir=$(INFRA_DIR) destroy -auto-approve

fmt:
	terraform -chdir=$(INFRA_DIR) fmt -recursive

validate: check-id
	terraform -chdir=$(INFRA_DIR) validate

k8s: check-id check-bin
	printf 'STUDENT_ID=%s\n' "$(STUDENT_ID)" > $(K8S_OVERLAY)/secret.env
	kubectl apply -k $(K8S_OVERLAY)

k8s-down:
	kubectl delete -k $(K8S_OVERLAY) --ignore-not-found || true
