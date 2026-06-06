output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "ecr_repositories" {
  value = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "rds_endpoints" {
  value = { for k, v in aws_db_instance.services : k => v.address }
}

output "redis_endpoint" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "sqs_queue_url" {
  value = aws_sqs_queue.analytics.url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.analytics.name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
