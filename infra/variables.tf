variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = "ai-civ-cluster"
}

variable "service_name" {
  description = "ECS service name"
  type        = string
  default     = "ai-civ-worker"
}

variable "container_port" {
  description = "Container port"
  type        = number
  default     = 8000
}

variable "cpu_high_threshold" {
  description = "CPU utilization high threshold for recovery"
  type        = number
  default     = 85
}

variable "cpu_low_threshold" {
  description = "CPU utilization low threshold for scale-down"
  type        = number
  default     = 30
}

variable "queue_depth_threshold" {
  description = "SQS queue depth threshold for simulation backpressure"
  type        = number
  default     = 5000
}

variable "tick_rate_reduction_factor" {
  description = "Factor to reduce simulation tick rate (0-1)"
  type        = number
  default     = 0.5
}

variable "health_check_interval" {
  description = "Health check interval in minutes"
  type        = number
  default     = 5
}

variable "deployment_circuit_breaker_enabled" {
  description = "Enable ECS deployment circuit breaker"
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}
