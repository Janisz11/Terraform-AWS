terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "order-system-vpc"
    Project = "lista6"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "order-system-igw"
    Project = "lista6"
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name    = "order-system-public-${count.index + 1}"
    Project = "lista6"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "order-system-public-rt"
    Project = "lista6"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "order-system-alb-sg"
  description = "Allow HTTP from internet to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "order-system-alb-sg"
    Project = "lista6"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "order-system-ecs-sg"
  description = "Allow traffic from ALB and internal service-to-service"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Internal service-to-service"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "order-system-ecs-sg"
    Project = "lista6"
  }
}

resource "aws_security_group" "rds" {
  name        = "order-system-rds-sg"
  description = "Allow PostgreSQL from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "order-system-rds-sg"
    Project = "lista6"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "order-system-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name    = "order-system-db-subnet-group"
    Project = "lista6"
  }
}

resource "aws_db_instance" "main" {
  identifier        = "order-system-db"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "gateway_db"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = true
  skip_final_snapshot = true
  multi_az            = false

  tags = {
    Name    = "order-system-db"
    Project = "lista6"
  }
}

# NOTE: The local-exec psql provisioner may fail if the machine running terraform apply
# cannot reach RDS (e.g. CloudShell with no direct RDS access).
# In that case, create databases manually by running a one-off ECS task:
# aws ecs run-task --cluster order-system-cluster --launch-type FARGATE \
#   --network-configuration "awsvpcConfiguration={subnets=[SUBNET_ID],securityGroups=[ECS_SG_ID],assignPublicIp=ENABLED}" \
#   --task-definition order-system-api_gateway \
#   --overrides '{"containerOverrides":[{"name":"api_gateway","command":["python3","-c",
#     "import asyncio,asyncpg; async def main(): conn=await asyncpg.connect(host=RDS_HOST,
#      user=postgres,password=PASSWORD,database=gateway_db,ssl=require);
#      [await conn.execute(f\"CREATE DATABASE {db}\") for db in [orders_db,inventory_db,payment_db]]
#     asyncio.run(main())"]}]}'
resource "null_resource" "create_databases" {
  depends_on = [aws_db_instance.main]

  provisioner "local-exec" {
    command = <<-EOT
      for DB in orders_db inventory_db payment_db; do
        PGPASSWORD='${var.db_password}' psql \
          -h ${aws_db_instance.main.address} \
          -U ${var.db_username} \
          -d gateway_db \
          -c "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1 \
          || PGPASSWORD='${var.db_password}' psql \
               -h ${aws_db_instance.main.address} \
               -U ${var.db_username} \
               -d gateway_db \
               -c "CREATE DATABASE $DB;"
      done
    EOT
  }
}

resource "aws_dynamodb_table" "notifications" {
  name         = "notifications"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name    = "notifications"
    Project = "lista6"
  }
}

resource "aws_s3_bucket" "files" {
  bucket = var.s3_bucket_name

  tags = {
    Name    = "order-system-files"
    Project = "lista6"
  }
}

resource "aws_s3_bucket_public_access_block" "files" {
  bucket = aws_s3_bucket.files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ecr_repository" "services" {
  for_each = toset(var.service_names)

  name                 = "order-system-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name    = "order-system-${each.key}"
    Project = "lista6"
  }
}
