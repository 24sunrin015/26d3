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
    [aws_autoscaling_group.stress.name],
  )
}
# apps/stress 분리 (ops 대시보드는 위 통합 리스트를 그대로 쓰고, nodes 대시보드가 이걸 씀)
output "apps_node_asg_names" {
  value = aws_eks_node_group.apps.resources[0].autoscaling_groups[*].name
}
output "stress_node_asg_name" {
  value = aws_autoscaling_group.stress.name
}
