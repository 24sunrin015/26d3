# Wave 2: Edge behavior

- Dynamic API traffic traverses CloudFront → ALB-attached WAF → ALB route → pod; `/images/*` bypasses WAF/ALB/EKS and reaches S3 via OAC.
- Ordinary unmatched GET returns ALB 404, confirmed live. WAF-global method/UA/managed rules can nevertheless return 403 before ALB for some unmatched paths.
- Product API GET is not cached; only `/images/*` uses optimized caching.
- Email rule uses `STARTS_WITH /v1/user`, creating an edge case where `/v1/useranything` can be 403 instead of unsupported-path 404.
- Current binary confirms `S3_BUCKET`, but bucket emptiness leaves object-key and PUT→GET behavior unresolved.

## EXPAND
- Closed by live checks: health 200, ordinary 404, invalid-email 403, all TGB targets healthy.
- Open external/live mutation: product image PUT→S3→CloudFront GET.
- Open policy boundary: exact malicious-header corpus requires user consultation.
