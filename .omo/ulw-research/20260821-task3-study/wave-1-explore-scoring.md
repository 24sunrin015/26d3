# Wave 1: Scoring specification

## Findings
- `taskfiles/task.md` and `taskfiles/mark.md` are authoritative; `guide.md` is a later local interpretation and explicitly subordinate.
- Official points are 4 abnormal/image, 12 availability, 12 performance, 12 cost.
- Official SLOs: user/product 0.2s, stress 1.0s, availability horizon 5s; all measured at client arrival.
- The 30% performance gate for all three APIs is official in `mark.md:190-205`.
- Baseline 2, continuous averaging, and EC2-worker-only counting are inferred in `guide.md:24-69`, not defined in the official 2026 mark sheet.
- `mark.md:178` is a high-confidence typo: row 3-17 says product 90%, but sequence indicates stress 90%.

## EXPAND
- Actual results/grader output is absent, so cost denominator, sampling, image semantics, and traffic corpus remain unresolved.
- Delivered product binary must establish S3 env key/object path.
- Malicious header signatures require user/official-source consultation.
