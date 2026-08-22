# Claim Graph

## Verified claims

- C-01, C-02, C-03, C-04 are supported by primary source and/or execution.
- C-05 is partial: node topology is verified, scored cost semantics and autoscaling transition are not.
- C-06 is partial: consultation constraint is supported, but current provisional WAF rules already encode unconfirmed patterns.

| claim_id | statement | type | risk | scope | intent ids | supports | contradictions | groups | convergence | counter-search | primary source | dependencies | status | synthesis |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| C-01 | `task.md` governs conflicts with supplementary guidance | specification precedence | high | requirements | I-01 | O-01 | none | spec, history | converged | no stronger source found | `taskfiles/task.md`, `guide.md:3-6` | none | supported | SYNTHESIS §Authority |
| C-02 | CloudFront is the single external endpoint and routes API traffic to ALB and image traffic to S3 | architecture | high | edge | I-02 | O-02, O-03, O-11 | none | code, guide, live | converged | live health/404 agree | Terraform source and live endpoint | TGB/ALB verified | supported | SYNTHESIS §Architecture |
| C-03 | Default infrastructure complies with EKS/EC2/RDS/S3 hard constraints | compliance | high | infra | I-03 | O-04, O-08, O-12 | none | code, spec, live | converged | forbidden-resource search negative | task.md, Terraform/state | remote snapshot | supported | SYNTHESIS §Architecture |
| C-04 | The documented double blocker is incomplete for standalone `make apply` | operational defect | high | Makefile | I-04 | O-05, O-10 | README says apply is protected | source, execution | converged | alternate empty PROVIDED dry-run | `Makefile` | none | supported | SYNTHESIS §Risks |
| C-05 | The node-group design runs two nodes at idle and can reach three for stress, but app HPA scale-out is unschedulable | scaling | high | runtime | I-05 | O-06, O-12 | cost semantics unresolved | code, live | topology converged; score partial | grader absent | Terraform/Kubernetes/live nodes | official grader | partial | SYNTHESIS §Scaling |
| C-06 | Malicious traffic defense is unresolved; current concrete UA rules conflict with the prior-consultation policy and carry 403/404/false-positive risks | process/security | high | security | I-06 | O-07, O-11 | ten regex groups already exist | policy, code, live | behavior partial | attack corpus absent | `AGENTS.md`, WAF source | user consultation | partial | SYNTHESIS §Risks |
