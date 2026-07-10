output "vpc_id" {
  value = aws_vpc.this.id
}
output "public_subnets" {
  value = aws_subnet.public[*].id
}
output "private_subnets" {
  value = aws_subnet.private[*].id
}
output "private_route_table_ids" {
  value = aws_route_table.private[*].id
}
