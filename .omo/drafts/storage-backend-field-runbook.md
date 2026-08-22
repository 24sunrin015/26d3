---
slug: storage-backend-field-runbook
status: drafting
intent: clear
review_required: false
pending-action: write .omo/plans/storage-backend-field-runbook.md
approach: Produce one field runbook for an additional externally routed API binary. It identifies the delivered binary's route and storage contract, maps it to the minimum dedicated Deployment/Service/TargetGroup/ServiceAccount/IaC changes, and preserves the required user/product RDS deployment.
---

# Draft: storage-backend-field-runbook

## Components (topology ledger)
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->
| binary-contract | Identify listener, route, environment variables, protocol, and storage client from the delivered binary before configuration changes | active | taskfiles/task.md:85; analysis/2026-strategy/product-s3-put.md |
| external-routing | Route the additional API through its own Service, target group, and TargetGroupBinding without replacing product | active | infra/terraform/modules/alb/main.tf; infra/k8s/overlays/prod/targetgroupbindings.yaml.tmpl |
| datastore-decision | Select the smallest proven integration path for MySQL, DynamoDB, DocumentDB, ElastiCache, or no datastore | active | infra/terraform/main.tf; infra/k8s/scripts/deploy.sh |
| workload-identity-network | Give only the new workload the required IAM permissions and private datastore reachability | active | infra/terraform/main.tf; infra/k8s/base/product.yaml |
| node-placement | Preserve the two-node baseline unless measurements show the new workload causes CPU or memory contention | active | infra/terraform/modules/eks/main.tf; infra/terraform/modules/eks/stress-nodegroup.tf |
| field-verification | Verify a real storage operation and service health before submitting the endpoint | active | taskfiles/guide.md; analysis/2026-strategy/product-s3-put.md |

## Open assumptions (announced defaults)
<!-- Record any default you adopt instead of asking, so the user can veto it at the gate. -->
<!-- assumption | adopted default | rationale | reversible? -->
| Existing user/product RDS remains mandatory | Do not replace or remove RDS for user/product | Current task grading zeroes performance and cost if DB type/count diverges | no |
| Unknown binary is a public API workload | Place it as a separate Deployment, Service, target group, TargetGroupBinding, and explicit ServiceAccount | User confirmed a binary must be added to EKS and exposed under its delivered API route | no |
| Managed datastore starts with one private endpoint/cluster path | Add only resources and permissions proven by the binary's runtime contract | Cost and resource minimization are scoring constraints | yes |

## Findings (cited - path:lines)

- `taskfiles/task.md:65-83` requires user and product to use MySQL RDS; `taskfiles/guide.md:163-174` states a DB type/count violation can zero performance and cost scoring.
- `infra/terraform/modules/eks/main.tf:118-136` fixes the `apps` node group at one `t3.medium`; `infra/terraform/modules/eks/stress-nodegroup.tf:75-143` reserves the autoscaled warm-pool path for stress.
- `infra/k8s/base/user.yaml:18-31` and `infra/k8s/base/product.yaml:24-39` place user/product on `role=apps`; only product has an S3 IRSA ServiceAccount.
- `infra/terraform/main.tf:55-89` grants S3 only to `default:product-sa`; DynamoDB, DocumentDB, and ElastiCache are absent from the current IaC.
- `infra/k8s/scripts/deploy.sh:18-48` is the binary-facing environment injection point.
- User confirmed the delivered binary is an additional externally routed API, possibly under `/v1/newapp` or `/v2/product`; it is never a replacement for the existing product workload.

## Decisions (with rationale)

- Keep RDS and its MySQL variables intact for the required user/product workloads.
- Treat the additional binary as a fourth app. Give it a distinct Kubernetes Deployment, Service, target group, TargetGroupBinding, image substitution, and ServiceAccount.
- Treat `/v1/newapp` and `/v2/product` as runtime-discovered ALB path-rule variants. The runbook will identify the exact path before the resource is applied.
- Model DynamoDB, DocumentDB, ElastiCache, and no-store as mutually exclusive, evidence-gated branches for an additional binary.
- Keep a storage client on the existing apps node by default. Managed datastore access does not justify a dedicated EC2 node; add a new node group only after a real workload measurement proves CPU or memory contention.
- Separate workload identity per binary. Do not attach DynamoDB or cache permissions to `product-sa` merely because a new binary needs them.

## Scope IN

- A field-time static/dynamic binary inspection sequence.
- Additional API routing through the current CloudFront → ALB → EKS path.
- Per-store evidence gates, environment contracts, networking, identity, and minimal resource changes.
- Node-placement and scaling decision rules that preserve the cost baseline.
- Explicit deployment and verification conditions.

## Scope OUT (Must NOT have)

- Replacing the required user/product RDS with another datastore.
- Replacing, renaming, or routing over the existing product Deployment, Service, target group, or TargetGroupBinding.
- Pre-provisioning DynamoDB, DocumentDB, ElastiCache, extra nodes, or broad IAM permissions without binary evidence.
- Combining a new binary's permissions with the existing product S3 role.

## Open questions

- None. Exact API route, listener, healthcheck, environment keys, and datastore are field-time evidence gates, not owner decisions.

## Approval gate
status: awaiting-approval
approach: Create a new field runbook for a fourth, externally routed binary. Cover binary inspection; `/v1/newapp` and `/v2/product` ALB-route variants; dedicated workload identity; per-datastore IaC branches; node-capacity rules; and end-to-end verification without changing existing user/product/stress behavior.
next: On approval, write the decision-complete plan artifact only. Execution remains a separate session.
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
