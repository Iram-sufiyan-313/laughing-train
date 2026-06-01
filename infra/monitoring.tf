# CloudWatch Dashboard for Self-Healing System
resource "aws_cloudwatch_dashboard" "sim_dashboard" {
  dashboard_name = "ai-civ-self-healing"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", { stat = "Average" }],
            [".", "MemoryUtilization", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "🧠 ECS CPU & Memory"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", { stat = "Average" }],
            [".", "ApproximateNumberOfNotVisibleMessages", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "📊 Queue Depth"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "RunningCount", { stat = "Average" }],
            [".", "DesiredCount", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "🚀 Task Count"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AICiv/Health", "SystemHealth", { stat = "Average" }],
            [".", "RecoveryActionsTriggered", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "❤️ System Health & Recovery"
        }
      }
    ]
  })
}

# Log Insights Queries
resource "aws_cloudwatch_log_resource_policy" "sim_log_policy" {
  policy_name = "ai-civ-log-policy"
  
  policy_text = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action   = "logs:PutLogEvents"
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/ecs/*"
      }
    ]
  })
}
