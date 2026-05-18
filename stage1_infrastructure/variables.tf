variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "db_username" {
  description = "Master username for RDS PostgreSQL"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Master password for RDS PostgreSQL"
  type        = string
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for file storage"
  type        = string
  default     = "cloud-lista6-files"
}

variable "service_names" {
  description = "List of microservice names"
  type        = list(string)
  default = [
    "api_gateway",
    "order_service",
    "inventory_service",
    "payment_service",
    "notification_service",
  ]
}
