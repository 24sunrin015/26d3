# Wave 1: Operational workflow

## Findings
- Actual sequence: set ID → apply → images → deploy → seed required dump → optional image upload → public smoke test → endpoint submission → monitor → teardown.
- `make up` omits DB seed and S3 image upload.
- README/AGENTS claim `apply` has both blockers, but `Makefile:44-45` only checks ID. `up`, `images`, and `deploy` check binaries.
- `db-seed.sh:9-11` has stale text claiming apply creates schema; current Terraform does not.
- `db-seed.sh` always analyzes both tables, so a one-table dump can fail if the other table does not exist.
- Deploy success proves only Kubernetes rollout, not ALB target health, WAF, RDS data, CloudFront, or S3.

## EXPAND
- Static blocker behavior and script syntax should be executed directly.
- Live and external grader validation is unavailable in this directory.
