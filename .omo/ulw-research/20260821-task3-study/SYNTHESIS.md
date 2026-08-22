# ULW Research Synthesis: task3 System Operation

Workers: 8 · Waves: 2 · Primary local sources: 3 · Execution verification: 1 static/live bundle

## Executive summary

This repository is a competition-oriented AWS/EKS deployment scaffold for the 2026 System Operation task. Its public flow is `Client → CloudFront → ALB/WAF → EKS` for APIs and `Client → CloudFront → S3` for `/images/*`. EKS workloads use one private Multi-AZ MySQL RDS for user/product, product receives S3 access through IRSA, and monitoring combines EKS control-plane logs, ALB logs/Athena, WAF logs, RDS logs, CloudWatch alarms, and a dashboard. The current live endpoint, three pods, HPAs, TargetGroupBindings, and ALB targets are healthy. [S4][S5][S7][S8][S9][S11][V1]

The currently configured topology uses two active `t3.medium` nodes: one fixed apps node for user/product and one dedicated stress node. Source configures a stopped warm-pool instance intended for promotion into a third active node, but its live presence and promotion were not verified. User/product HPAs are misleading: the live apps node has only 456m unallocated requested CPU, less than either app's 512m replica request, and the apps node group cannot grow. Stress scaling is structurally coherent but its actual 1→2→1 transition and cost impact have not been load-tested in this research. [S5][S6][V1]

The most important unresolved facts are external by design: the official cost-ratio formula/sampling and warm-pool treatment, the exact scored traffic distribution, a real product image PUT→S3→CloudFront GET chain, and the malicious-header corpus. Project policy requires discussing concrete patterns and defense rules with the user, yet the current WAF already contains ten concrete User-Agent regex groups; that is an existing implementation-policy conflict, not merely a constraint on future changes. [S2][S3][S7][S12]

## Authority and scoring

`taskfiles/task.md` and `taskfiles/mark.md` are primary. `guide.md` explicitly describes itself as a supplementary interpretation. Officially confirmed: 40 total points split 4/12/12/12; user/product SLO 0.2s, stress 1.0s; client-arrival measurement; cumulative threshold ladders; and all three performance values ≥30% for every cost point. [S1][S2]

The common formula `average EC2 worker nodes / baseline 2`, worker-only counting, and continuous traffic-window averaging come only from `guide.md`, based on prior-year reverse engineering. They are useful operating assumptions but not official 2026 facts. `mark.md` also contains an internal 3-17 contradiction: the criteria table says stress ≥90%, while the detailed row says product ≥90%; sequence implies a typo but the grader is absent. [S2][S3]

## Architecture and data flow

1. CloudFront is the submitted HTTPS endpoint. Dynamic behavior disables caching and forwards to an ALB; `/images/*` goes to private S3 through OAC and strips the `/images` prefix. Product API GET is not cached. [S4]
2. The ALB accepts traffic only from the CloudFront origin-facing prefix list, routes `/v1/user`, `/v1/product`, and `/v1/stress` to IP target groups, and returns fixed 404 for ordinary unmatched paths. TargetGroupBindings register pod IPs. [S7][S13]
3. Regional WAF is attached to ALB, so API traffic is inspected but image downloads bypass it. Invalid-email POST is 403 live; ordinary missing path is 404 live. Global managed/method/UA rules can still turn some unsupported-path requests into 403 before ALB. [S7][V1]
4. One private Multi-AZ MySQL 8.0 `db.t3.micro` gp3 RDS serves user/product. It permits EKS-node ingress, exports error/slow logs, and uses a tuned parameter group. [S1][S8][S14]
5. Product's `product-sa` receives bucket-scoped read/write/delete/list via IRSA. Current product binary embeds `S3_BUCKET` and AWS region variables, but the bucket is empty and key behavior is unverified. [S9][V1]

## Runtime and scaling

Live state contains exactly two Ready nodes and three Ready application pods. User/product share `role=apps`; stress runs on `role=stress`. Every ALB target is healthy. [V1]

| Surface | Current | Scale path | Key constraint |
|---|---|---|---|
| apps node | 1930m allocatable, 1474m requested | none; managed group fixed at 1 | extra app replica requests 512m but only 456m remains |
| stress node | 1930m allocatable, 1650m requested | HPA 1→2 creates Pending 1500m pod; CA can raise stress ASG 1→2 | warm-pool promotion and SLO recovery time unmeasured |
| active workers | 2 idle, source permits 3 peak | third node only for stress | official grader counting remains unknown |

The deployment's rolling `maxSurge:1` also competes with this tight apps-node capacity. A repeat deployment can stall if a surge pod cannot schedule. [S6][V1]

## Operator workflow

The reliable sequence is: set `STUDENT_ID`; inspect supplied binaries; validate/plan/apply; build/push images; deploy; seed the required user dump; optionally upload supplied images; verify public health/API/WAF/image behavior and target health; submit the endpoint; monitor HPA/nodes/WAF/RDS; stop tests before authorized teardown. [S1][S10]

`make up` omits DB seeding and image upload. `deploy.sh` proves only Kubernetes rollout, not public edge correctness. Generated config/secret/TGB files and Terraform state are local/ignored. Images use mutable `latest`, and unchanged pod templates/config names do not guarantee a fresh rollout. [S10]

## High-impact risks

1. **Standalone `make apply` violates the documented double-blocker contract.** It checks ID but not binaries; command execution confirmed this. [S10][V1]
2. **App HPAs cannot currently scale.** Both extra replicas are unschedulable on the fixed apps node; no compatible CA path exists. [S5][S6][V1]
3. **Image score is currently unproven.** S3 is empty; no real product PUT or `/images/<key>` 200 was observed. [S4][S9][V1]
4. **DB seed documentation is stale.** Terraform no longer creates schema, but `db-seed.sh` comments say it does; the post-SQL always analyzes both tables. [S10]
5. **WAF semantics and policy conflict are broader than the simple 403/404 rule.** `STARTS_WITH /v1/user` and global rules can preempt ALB 404; broad UA substrings can false-positive. More fundamentally, AGENTS says patterns/rules are unconfirmed and require prior user consultation, while current Terraform already implements ten concrete UA regex groups. No new rule was added in this research. [S7][S12]
6. **Cost claims remain inferred.** Two active nodes are observable, but baseline, sample window, and stopped warm-pool treatment are not official in this repository. [S2][S3]

## Verified claims

- Terraform validate, Kustomize render/client dry-run, and shell syntax passed. [V1]
- Public health returned 200, ordinary unsupported path 404, and invalid email 403. [V1]
- Three deployments, HPAs, TGBs, and ALB targets are live and healthy. [V1]
- Current binaries are static linux/amd64 ELF; product uses Go 1.25.5 and embeds `S3_BUCKET`. [V1]
- Two Ready nodes expose 1930m allocatable CPU each; current request totals are 1474m apps and 1650m stress. [V1]

## Gaps and explicit abstentions

- No claim is made that the system meets scored SLO percentages under load.
- No claim is made that the stopped warm-pool instance is cost-free to the grader.
- No claim is made that image downloads work until a real object/PUT chain is observed.
- No WAF attack-header change was designed or implemented because the local policy requires prior user discussion.
- No infrastructure or application source was changed; only this research journal was created.

## Sources

- [S1] `taskfiles/task.md`: official task requirements and SLOs.
- [S2] `taskfiles/mark.md`: official point thresholds and cost gates.
- [S3] `taskfiles/guide.md`: explicitly interpretive cost/metric model.
- [S4] `infra/terraform/modules/cloudfront/main.tf`: edge split, cache policy, image rewrite/OAC.
- [S5] `infra/terraform/modules/eks/main.tf`, `stress-nodegroup.tf`, `addons.tf`: node topology and controllers.
- [S6] `infra/k8s/base/user.yaml`, `product.yaml`, `stress.yaml`: resources, scheduling, probes, HPAs.
- [S7] `infra/terraform/modules/waf/main.tf`, `modules/alb/main.tf`: WAF and route status behavior.
- [S8] `infra/terraform/modules/rds/main.tf`: database implementation.
- [S9] `infra/terraform/main.tf`, `infra/k8s/scripts/deploy.sh`: product IRSA and runtime env wiring.
- [S10] `Makefile`, `scripts/db-seed.sh`, `scripts/upload_images.sh`, `TROUBLESHOOTING.md`: operator workflow and contradictions.
- [S11] `infra/terraform/modules/monitoring/dashboard.tf`, `alarms.tf`, `athena.tf`: monitoring implementation.
- [S12] `AGENTS.md:33-41`: mandatory user-consultation boundary for malicious-header rules.
- [S13] `infra/k8s/overlays/prod/targetgroupbindings.yaml.tmpl`: pod-IP TargetGroupBinding definitions.
- [S14] `infra/terraform/variables.tf:63-92`: required/default RDS class, engine, and storage inputs.
- [V1] `verify-static-and-live.md`: executed static and live evidence from 2026-08-21.

## Expansion trace

Wave 1 covered scoring, operations, infrastructure, and Kubernetes runtime. Wave 2 covered scoring ambiguity, edge behavior, deployment reliability, and capacity arithmetic. Repository leads converged; remaining leads require external grader artifacts, controlled load/state mutation, an image object/PUT, or user consultation.

## Research-process disclosure

An initial Codegraph query scoped to task3 returned unrelated indexed repository paths. Those paths were not used in the synthesis; every affected task3 observation was re-established through direct in-scope reads. The out-of-scope tool return nevertheless violated the directory-access constraint and is explicitly disclosed here rather than hidden.
