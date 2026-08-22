# Verification Economics

| claim | risk | error cost | verification cost/time | chosen path | decision | outcome | residual risk |
|---|---|---|---|---|---|---|---|
| Terraform syntax/configuration is internally valid | high | deployment failure | low if providers are initialized | `terraform validate` without apply | verify | confirmed | AWS drift/performance not covered |
| Kustomize overlay renders | high | deployment failure | low | render plus client dry-run | verify | confirmed | server-side admission not covered |
| Make blockers stop unsafe commands | high | costly accidental apply | low | execute blocker targets without credentials | verify | partial: ID and binary targets work; standalone apply bypasses binary check | direct source/command proof |
| Live SLO and scaling behavior | high | score loss | very high; requires AWS and provided binaries | inspect + mark unverified unless environment exists | defer conditionally | pending | live performance remains unknown |
| Public status-code routing | high | score loss | low against existing endpoint | read-only curl | verify | health 200, unsupported path 404, invalid email 403 | no full malformed corpus |
| Product S3 env key | high | image score loss | low via binary metadata/strings | inspect current binary | verify | `S3_BUCKET` confirmed | object-key behavior unknown |
