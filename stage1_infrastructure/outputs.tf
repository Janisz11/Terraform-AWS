output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "ecs_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs_tasks.id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "rds_host" {
  description = "RDS instance endpoint hostname"
  value       = aws_db_instance.main.address
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB notifications table"
  value       = aws_dynamodb_table.notifications.name
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.files.bucket
}

output "ecr_repository_urls" {
  description = "ECR repository URLs keyed by service name"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}
