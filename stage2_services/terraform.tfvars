aws_region = "us-east-1"

vpc_id                = "vpc-0e46b6d21932128cf"
public_subnet_ids     = ["subnet-0f8756d5a10a68156", "subnet-06b47ec63cd74123f"]
ecs_security_group_id = "sg-0794330ea7b2f0f95"
alb_security_group_id = "sg-08e0ed646369c4c52"

rds_host            = "order-system-db.c1g0ywgocgub.us-east-1.rds.amazonaws.com"
dynamodb_table_name = "notifications"
s3_bucket_name      = "cloud-lista6-files"

db_username = "postgres"
db_password = "Postgres123!"

rabbitmq_url = "amqps://dlaiuuvz:taNWPMquR_2fgKnOVq3oBtiGPzwLhcoQ@kebnekaise.lmq.cloudamqp.com/dlaiuuvz"

order_service_ip        = "10.0.1.179"
inventory_service_ip    = "10.0.0.136"
payment_service_ip      = "10.0.1.178"
notification_service_ip = "10.0.0.215"
