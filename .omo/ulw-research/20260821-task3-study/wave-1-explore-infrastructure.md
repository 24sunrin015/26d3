# Wave 1: Infrastructure topology

## Findings
- Client → CloudFront → ALB/WAF → EKS for APIs; CloudFront → private S3 via OAC for images.
- Two-AZ VPC, one NAT, private EKS/RDS, S3 gateway endpoint.
- One managed apps node plus one self-managed stress node; stress ASG can add one active node and maintains a stopped warm-pool member.
- One private Multi-AZ MySQL 8.0 db.t3.micro gp3 instance with CloudWatch error/slow logs.
- Monitoring includes dashboards, alarms, ALB logs/Athena, WAF logs, EKS control-plane logs; app log shipping is optional/off.
- High risks: fixed apps capacity vs HPAs, unresolved S3 contract, broad WAF UA patterns, and local/generated sensitive state.

## EXPAND
- Determine warm-pool/node-count uncertainty and actual schedulability.
- Distinguish official scoring claims from repository assumptions.
- Verify Terraform and Kustomize statically.
