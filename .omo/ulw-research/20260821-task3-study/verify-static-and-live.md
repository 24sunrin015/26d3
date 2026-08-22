# Verification: Static and Live Surfaces

Observed 2026-08-21 from the task3 workspace. No infrastructure mutation or load test was performed.

## Static configuration

- `terraform -chdir=infra/terraform validate`: PASS, configuration valid.
- `kubectl kustomize infra/k8s/overlays/prod`: PASS.
- Client-side Kubernetes dry-run of the rendered manifests: PASS.
- `bash -n` for build, deploy, DB seed, and upload scripts: PASS.
- `bash scripts/db-seed.sh --help`: PASS.

## Safety behavior

- `make check-id` without `STUDENT_ID`: correctly fails.
- `make check-bin` with an empty alternate `PROVIDED`: correctly reports all three missing binaries.
- `make -n apply PROVIDED=<empty> STUDENT_ID=research`: still reaches Terraform apply and never invokes `check-bin`, proving the documented double blocker is absent from standalone `apply`.
- Current `provided/user`, `product`, `stress` are statically linked x86-64 Linux ELF binaries.

## Public and cluster surface

- Endpoint: `https://d1guzt9wa99alh.cloudfront.net`.
- `GET /healthcheck`: HTTP 200 in 0.160924s.
- `GET /v1/none`: HTTP 404 in 0.057376s.
- Invalid-email `POST /v1/user`: HTTP 403 in 0.069301s.
- The invalid-email request was intended to terminate at WAF; no terminating-rule log or DB audit was captured, so application-data nonmutation is not independently proven.
- Kubernetes: all three Deployments are 1/1 Ready; three HPAs report CPU; three TargetGroupBindings exist.
- Placement: user/product share the `role=apps` node; stress runs on `role=stress`; exactly two Ready nodes observed.
- ALB target health: user, product, and stress pod IP targets all `healthy`.
- Idle utilization: apps node 2% CPU/19% memory; stress node 1% CPU/13% memory.
- Image bucket contains no object, so `/images/<object>` behavior and image score remain unverified.

## Binary contract

- Direct `./provided/product --help` failed on macOS with `exec format error`, as expected for a Linux ELF.
- Go metadata: linux/amd64, CGO disabled, Go 1.25.5, AWS SDK v2 S3 dependency present.
- Binary strings include `S3_BUCKET`, `AWS_REGION`, and `AWS_DEFAULT_REGION`; `S3_BUCKET` is therefore the confirmed bucket env key for the current training binary.
- Object-key prefix/upload form and real PUT→S3→CloudFront GET remain unverified.

## Limits of evidence

- Local Terraform state proves tracked intent, not remote drift-free health.
- No scored load was injected; SLO percentages, HPA/CA transition time, third-node behavior, RDS saturation, and cost ratio remain unverified.
- No official grader/results log exists in task3, so the guide's baseline and sampling interpretation remains inferred.
- An initial Codegraph call returned indexed paths outside task3 despite a task3 project path. Those unrelated results were not used; all affected observations were re-established by direct reads inside task3. The out-of-scope tool return is disclosed as a process violation.
