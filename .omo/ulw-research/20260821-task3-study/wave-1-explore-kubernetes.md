# Wave 1: Kubernetes runtime

## Findings
- Runtime chain: provided binaries → amd64 images → ECR → rendered Kustomize → Deployments/Services → TargetGroupBindings → ALB.
- Rendered set contains three Deployments, Services, HPAs, and TargetGroupBindings plus product ServiceAccount, ConfigMap, and Secret.
- User/product share one fixed apps node; stress is isolated to a tainted stress ASG and scales HPA→Pending→Cluster Autoscaler.
- `/images/*` bypasses ALB/WAF/EKS and goes CloudFront→S3.
- Key risks: mutable `latest`, no rollout trigger for unchanged pod templates/config, no app-node scale-out, no live edge/TGB validation in deploy script, and unknown product binary contract.

## EXPAND
- Verify current binaries and live edge only when delivered/running.
- Measure HPA-to-healthy-target latency only in a live cluster.
- Audit generated-state and scheduling arithmetic in the next wave.
