variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID (from stage1 output: vpc_id)"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (from stage1 output: public_subnet_ids)"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "ECS tasks security group ID (from stage1 output: ecs_security_group_id)"
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB security group ID (from stage1 output: alb_security_group_id)"
  type        = string
}

variable "rds_host" {
  description = "RDS instance hostname (from stage1 output: rds_host)"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name (from stage1 output: dynamodb_table_name)"
  type        = string
  default     = "notifications"
}

variable "s3_bucket_name" {
  description = "S3 bucket name (from stage1 output: s3_bucket_name)"
  type        = string
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "rabbitmq_url" {
  description = "CloudAMQP connection URL (amqps://...)"
  type        = string
  sensitive   = true
}

variable "order_service_ip" {
  description = "Private IP of the running order_service ECS task"
  type        = string
}

variable "inventory_service_ip" {
  description = "Private IP of the running inventory_service ECS task"
  type        = string
}

variable "payment_service_ip" {
  description = "Private IP of the running payment_service ECS task"
  type        = string
}

variable "notification_service_ip" {
  description = "Private IP of the running notification_service ECS task"
  type        = string
}
