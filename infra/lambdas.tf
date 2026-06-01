# Health Monitor Lambda Function
resource "aws_lambda_function" "health_monitor" {
  filename      = data.archive_file.health_monitor_zip.output_path
  function_name = "ai-civ-health-monitor"
  role          = aws_iam_role.lambda_health_role.arn
  handler       = "health_monitor.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256
  
  environment {
    variables = {
      CLUSTER_NAME              = aws_ecs_cluster.sim_cluster.name
      SERVICE_NAME              = aws_ecs_service.sim_worker.name
      QUEUE_URL                 = aws_sqs_queue.sim_queue.url
      SNS_TOPIC_ARN             = aws_sns_topic.health_recovery.arn
      CPU_HIGH_THRESHOLD        = var.cpu_high_threshold
      CPU_LOW_THRESHOLD         = var.cpu_low_threshold
      QUEUE_DEPTH_THRESHOLD     = var.queue_depth_threshold
      TICK_RATE_REDUCTION       = var.tick_rate_reduction_factor
    }
  }
  
  tags = {
    Name = "health-monitor"
  }
  
  depends_on = [data.archive_file.health_monitor_zip]
}

# Health Recovery Handler Lambda
resource "aws_lambda_function" "health_recovery_handler" {
  filename      = data.archive_file.health_recovery_zip.output_path
  function_name = "ai-civ-health-recovery"
  role          = aws_iam_role.lambda_health_role.arn
  handler       = "health_recovery.lambda_handler"
  runtime       = "python3.11"
  timeout       = 120
  memory_size   = 256
  
  environment {
    variables = {
      CLUSTER_NAME         = aws_ecs_cluster.sim_cluster.name
      SERVICE_NAME         = aws_ecs_service.sim_worker.name
      QUEUE_URL            = aws_sqs_queue.sim_queue.url
    }
  }
  
  tags = {
    Name = "health-recovery"
  }
  
  depends_on = [data.archive_file.health_recovery_zip]
}

# Archive Lambda source files
data "archive_file" "health_monitor_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/health_monitor.py"
  output_path = "${path.module}/../lambda/health_monitor.zip"
}

data "archive_file" "health_recovery_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/health_recovery.py"
  output_path = "${path.module}/../lambda/health_recovery.zip"
}

# EventBridge Rule to trigger health monitor every 5 minutes
resource "aws_cloudwatch_event_rule" "health_monitor_schedule" {
  name                = "ai-civ-health-monitor-schedule"
  description         = "Trigger health monitor every 5 minutes"
  schedule_expression = "rate(5 minutes)"
  
  tags = {
    Name = "health-monitor-schedule"
  }
}

resource "aws_cloudwatch_event_target" "health_monitor_target" {
  rule      = aws_cloudwatch_event_rule.health_monitor_schedule.name
  target_id = "HealthMonitorLambda"
  arn       = aws_lambda_function.health_monitor.arn
  
  input = jsonencode({
    action = "health_check"
  })
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_monitor_schedule.arn
}
