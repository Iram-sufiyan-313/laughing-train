# CloudWatch Alarms for Auto-Recovery

# High CPU Alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "ai-civ-ecs-high-cpu"
  alarm_description   = "Alert when ECS CPU utilization is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_high_threshold
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ClusterName = aws_ecs_cluster.sim_cluster.name
    ServiceName = aws_ecs_service.sim_worker.name
  }
  
  alarm_actions = [aws_sns_topic.health_recovery.arn]
  
  tags = {
    Name = "ecs-high-cpu"
  }
}

# High Memory Alarm
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "ai-civ-ecs-high-memory"
  alarm_description   = "Alert when ECS memory utilization is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ClusterName = aws_ecs_cluster.sim_cluster.name
    ServiceName = aws_ecs_service.sim_worker.name
  }
  
  alarm_actions = [aws_sns_topic.health_recovery.arn]
  
  tags = {
    Name = "ecs-high-memory"
  }
}

# SQS Queue Depth Alarm (for backpressure)
resource "aws_cloudwatch_metric_alarm" "queue_depth_critical" {
  alarm_name          = "ai-civ-queue-depth-critical"
  alarm_description   = "Alert when queue depth exceeds threshold (backpressure trigger)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = var.queue_depth_threshold
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    QueueName = aws_sqs_queue.sim_queue.name
  }
  
  alarm_actions = [aws_sns_topic.health_recovery.arn]
  
  tags = {
    Name = "queue-depth-critical"
  }
}

# DLQ Messages Alarm (failed message processing)
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "ai-civ-dlq-messages-present"
  alarm_description   = "Alert when messages appear in DLQ (processing failures)"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    QueueName = aws_sqs_queue.sim_dlq.name
  }
  
  alarm_actions = [aws_sns_topic.health_recovery.arn]
  
  tags = {
    Name = "dlq-messages-alert"
  }
}

# Task Count Alarm (ensure minimum running tasks)
resource "aws_cloudwatch_metric_alarm" "task_count_low" {
  alarm_name          = "ai-civ-task-count-low"
  alarm_description   = "Alert when running task count drops below minimum"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ClusterName = aws_ecs_cluster.sim_cluster.name
    ServiceName = aws_ecs_service.sim_worker.name
  }
  
  alarm_actions = [aws_sns_topic.health_recovery.arn]
  
  tags = {
    Name = "task-count-low"
  }
}

# Service Deployment Status Alarm
resource "aws_cloudwatch_metric_alarm" "deployment_failures" {
  alarm_name          = "ai-civ-deployment-failures"
  alarm_description   = "Alert on ECS deployment failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedStarts"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ClusterName = aws_ecs_cluster.sim_cluster.name
    ServiceName = aws_ecs_service.sim_worker.name
  }
  
  alarm_actions = [aws_sns_topic.health_recovery.arn]
  
  tags = {
    Name = "deployment-failures"
  }
}
