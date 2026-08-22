# Observation Manifest

Observed at: 2026-08-21, repository working tree.

| observation_id | source | layer | group | independence | observer | observed_at | valid_at | artifact | anchor | contamination |
|---|---|---|---|---|---|---|---|---|---|---|
| O-01 | `taskfiles/guide.md` | specification | direct-spec | authoritative local document | Hephaestus | 2026-08-21 | current worktree | direct read | lines 3-6 | guide is explicitly secondary to task.md |
| O-02 | `infra/terraform/main.tf` | implementation | direct-code | Terraform source read directly within task3 | Hephaestus | 2026-08-21 | current worktree | direct read | lines 1-5, 129-157 | Earlier Codegraph output leaked unrelated indexed paths and is excluded from all evidence |
| O-03 | `taskfiles/guide.md` | interpretation | direct-spec | supplementary guide | Hephaestus | 2026-08-21 | current worktree | direct read | lines 83-90 | derived partly from prior-year operation |
| O-04 | `infra/terraform/variables.tf`, `modules/eks/main.tf`, `modules/rds/main.tf` | implementation | direct-code | Terraform source read directly within task3 | Hephaestus | 2026-08-21 | current worktree | direct read | variables 43-73; EKS 118-129; RDS 114-144 | remote drift handled separately by live snapshot |
| O-05 | `Makefile` | implementation | direct-code | Make entry points | Hephaestus | 2026-08-21 | current worktree | direct read | lines 11-32, 38-61 | no command execution yet |
| O-06 | `infra/terraform/variables.tf`, `modules/eks/stress-nodegroup.tf`, `infra/k8s/base/stress.yaml` | implementation | direct-code | source read directly within task3 | Hephaestus | 2026-08-21 | current worktree | direct read | variables 55-60; ASG 75-92; HPA 59-81 | transition behavior still requires load test |
| O-07 | `AGENTS.md`, `taskfiles/guide.md` | policy/spec | local-policy | two local documents | Hephaestus | 2026-08-21 | current worktree | supplied context/direct read | AGENTS §3; guide 123-139 | attack patterns intentionally unspecified |
| O-08 | Terraform CLI | execution | static-validation | compiler/provider schema | Hephaestus | 2026-08-21 | current worktree | `verify-static-and-live.md` | validate PASS | no remote plan |
| O-09 | kubectl client | execution | static-validation | Kustomize/client parser | Hephaestus | 2026-08-21 | current worktree | `verify-static-and-live.md` | render/dry-run PASS | generated files reflect current local state |
| O-10 | Make CLI | execution | operational-validation | executable target graph | Hephaestus | 2026-08-21 | current worktree | `verify-static-and-live.md` | blocker commands | dry-run did not mutate infrastructure |
| O-11 | CloudFront endpoint | execution | live-edge | public HTTP surface | Hephaestus | 2026-08-21 | live at observation | `verify-static-and-live.md` | 200/404/403 outcomes | single samples, no load |
| O-12 | EKS/ALB APIs | execution | live-runtime | Kubernetes and AWS control planes | Hephaestus | 2026-08-21 | live at observation | `verify-static-and-live.md` | ready pods/nodes/healthy targets | snapshot only |
| O-13 | `provided/product` | binary | binary-contract | ELF metadata and embedded strings | Hephaestus | 2026-08-21 | current binary | `verify-static-and-live.md` | linux/amd64, S3_BUCKET | key layout not proved |
