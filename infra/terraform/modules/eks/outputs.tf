output "cluster_name" {
  value = aws_eks_cluster.this.name
}
output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}
output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}
output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}
output "node_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
output "node_asg_names" {
  value = concat(
    aws_eks_node_group.apps.resources[0].autoscaling_groups[*].name,
    aws_eks_node_group.stress.resources[0].autoscaling_groups[*].name,
  )
}
