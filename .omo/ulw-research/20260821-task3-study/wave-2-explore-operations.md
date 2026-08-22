# Wave 2: Deployment reliability

- `make up` is bootstrap only: it omits mandatory user dump seeding and optional image upload.
- Standalone `apply` lacks the documented binary blocker; executable dry-run confirms this.
- Generated env/secret/manifests and local Terraform state can become stale; static validation does not establish freshness.
- Mutable `latest`, stable ConfigMap/Secret names, and unchanged pod templates make repeat deploy provenance unreliable.
- `k8s-down` neither refreshes kubeconfig nor reports delete failures.
- Current live reconciliation is healthy: three deployments, HPAs, TGBs, and ALB targets correspond to state outputs.

## EXPAND
- Closed: state/output-to-live target reconciliation.
- Open: destructive DB seed semantics and image chain should be exercised only with intended competition inputs.
