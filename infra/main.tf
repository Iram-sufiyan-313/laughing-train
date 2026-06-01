terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "ai-civ-terraform-state"
    key            = "self-healing/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "ai-civilization"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "SelfHealing"
    }
  }
}

# VPC and Networking
resource "aws_vpc" "sim_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "sim-vpc"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.sim_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "sim-private-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.sim_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
    Name = "sim-private-2"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Security Group for ECS
resource "aws_security_group" "ecs_sg" {
  name_prefix = "ecs-sim-"
  vpc_id      = aws_vpc.sim_vpc.id
  
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "ecs-sim-sg"
  }
}

# ECR Repository
resource "aws_ecr_repository" "worker" {
  name                 = "ai-civ-worker"
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  tags = {
    Name = "ai-civ-worker"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "sim_cluster" {
  name = "ai-civ-cluster"
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  
  tags = {
    Name = "ai-civ-cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "cluster_providers" {
  cluster_name           = aws_ecs_cluster.sim_cluster.name
  capacity_providers     = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/ai-civ-worker"
  retention_in_days = 30
  
  tags = {
    Name = "ecs-ai-civ-logs"
  }
}

# SQS Queue for Simulation Tasks
resource "aws_sqs_queue" "sim_queue" {
  name                      = "ai-civ-simulation-queue"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 86400
  receive_wait_time_seconds = 20
  
  tags = {
    Name = "sim-queue"
  }
}

# SQS Dead Letter Queue (DLQ)
resource "aws_sqs_queue" "sim_dlq" {
  name                      = "ai-civ-simulation-dlq"
  message_retention_seconds = 1209600  # 14 days
  
  tags = {
    Name = "sim-dlq"
  }
}

# Attach DLQ to main queue
resource "aws_sqs_queue_redrive_policy" "sim_queue_policy" {
  queue_url           = aws_sqs_queue.sim_queue.id
  dead_letter_queue_arn = aws_sqs_queue.sim_dlq.arn
  max_receive_count   = 3
}

# ECS Task Definition
resource "aws_ecs_task_definition" "sim_worker" {
  family                   = "ai-civ-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  
  container_definitions = jsonencode([
    {
      name      = "ai-civ-worker"
      image     = "${aws_ecr_repository.worker.repository_url}:latest"
      essential = true
      
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      
      environment = [
        {
          name  = "CLUSTER_NAME"
          value = aws_ecs_cluster.sim_cluster.name
        },
        {
          name  = "SERVICE_NAME"
          value = "ai-civ-worker"
        },
        {
          name  = "QUEUE_URL"
          value = aws_sqs_queue.sim_queue.url
        },
        {
          name  = "QUEUE_MAX_DEPTH"
          value = "5000"
        },
        {
          name  = "TICK_RATE_BASE"
          value = "100"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
  
  tags = {
    Name = "ai-civ-worker-task"
  }
}

# ECS Service with Circuit Breaker
resource "aws_ecs_service" "sim_worker" {
  name            = "ai-civ-worker"
  cluster         = aws_ecs_cluster.sim_cluster.id
  task_definition = aws_ecs_task_definition.sim_worker.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets          = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }
  
  # Circuit Breaker for Auto-Rollback
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  
  # Deployment Configuration
  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }
  
  # Enable ECS Exec for debugging
  enable_execute_command = true
  
  tags = {
    Name = "ai-civ-worker-service"
  }
  
  depends_on = [
    aws_iam_role_policy.ecs_task_role_policy
  ]
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.sim_cluster.name}/${aws_ecs_service.sim_worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy: SQS Queue Depth (Primary)
resource "aws_appautoscaling_policy" "queue_depth_scaling" {
  name               = "queue-depth-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "SQSQueueDepthPerTask"
      resource_label         = "${aws_sqs_queue.sim_queue.arn}:${aws_ecs_service.sim_worker.name}"
    }
    target_value = 10  # Scale up when queue has >10 messages per task
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Auto Scaling Policy: CPU Utilization (Secondary)
resource "aws_appautoscaling_policy" "cpu_scaling" {
  name               = "cpu-utilization-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# SNS Topic for Health Recovery Actions
resource "aws_sns_topic" "health_recovery" {
  name = "ai-civ-health-recovery"
  
  tags = {
    Name = "health-recovery-topic"
  }
}

resource "aws_sns_topic_subscription" "health_recovery_lambda" {
  topic_arn = aws_sns_topic.health_recovery.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.health_recovery_handler.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_recovery_handler.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.health_recovery.arn
}

# IAM Roles
resource "aws_iam_role" "ecs_task_execution_role" {
  name_prefix = "ecs-task-exec-"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_ecr_policy" {
  name_prefix = "ecs-ecr-"
  role        = aws_iam_role.ecs_task_execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name_prefix = "ecs-task-role-"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name_prefix = "ecs-task-policy-"
  role        = aws_iam_role.ecs_task_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.sim_queue.arn,
          aws_sqs_queue.sim_dlq.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_health_role" {
  name_prefix = "lambda-health-"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_health_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_health_policy" {
  name_prefix = "lambda-health-policy-"
  role        = aws_iam_role.lambda_health_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:UpdateService",
          "ecs:DescribeTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.sim_queue.arn,
          aws_sqs_queue.sim_dlq.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
