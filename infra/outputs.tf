output "ecr_repository_uri" {
  description = "ECR repository URI"
  value       = aws_ecr_repository.worker.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.sim_cluster.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.sim_worker.name
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = aws_sqs_queue.sim_queue.url
}

output "sqs_queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.sim_queue.arn
}

output "sqs_dlq_url" {
  description = "SQS Dead Letter Queue URL"
  value       = aws_sqs_queue.sim_dlq.url
}

output "health_monitor_lambda_arn" {
  description = "Health Monitor Lambda function ARN"
  value       = aws_lambda_function.health_monitor.arn
}

output "health_recovery_handler_arn" {
  description = "Health Recovery Handler Lambda function ARN"
  value       = aws_lambda_function.health_recovery_handler.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group for ECS"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}

output "sns_health_recovery_topic_arn" {
  description = "SNS topic for health recovery actions"
  value       = aws_sns_topic.health_recovery.arn
}
