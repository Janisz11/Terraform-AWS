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

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  ecr_base   = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  lab_role   = "arn:aws:iam::${local.account_id}:role/LabRole"

  service_ports = {
    api_gateway          = 8000
    order_service        = 8000
    inventory_service    = 8000
    payment_service      = 8000
    notification_service = 8000
  }

  db_urls = {
    api_gateway          = "postgresql+asyncpg://${var.db_username}:${var.db_password}@${var.rds_host}:5432/gateway_db?ssl=require"
    order_service        = "postgresql+asyncpg://${var.db_username}:${var.db_password}@${var.rds_host}:5432/orders_db?ssl=require"
    inventory_service    = "postgresql+asyncpg://${var.db_username}:${var.db_password}@${var.rds_host}:5432/inventory_db?ssl=require"
    payment_service      = "postgresql+asyncpg://${var.db_username}:${var.db_password}@${var.rds_host}:5432/payment_db?ssl=require"
    notification_service = "dynamodb"
  }
}

resource "aws_cloudwatch_log_group" "services" {
  for_each          = local.service_ports
  name              = "/ecs/order-system/${each.key}"
  retention_in_days = 7
  tags = { Project = "lista6" }
}

resource "aws_ecs_cluster" "main" {
  name = "order-system-cluster"
  tags = { Name = "order-system-cluster", Project = "lista6" }
}

resource "aws_ecs_task_definition" "services" {
  for_each = local.service_ports

  family                   = "order-system-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = local.lab_role
  task_role_arn            = local.lab_role

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = "${local.ecr_base}/order-system-${each.key}:latest"
      essential = true
      portMappings = [{ containerPort = each.value, hostPort = each.value, protocol = "tcp" }]
      environment = concat(
        [
          { name = "DATABASE_URL",   value = local.db_urls[each.key] },
          { name = "AWS_REGION",     value = var.aws_region },
          { name = "S3_BUCKET_NAME", value = var.s3_bucket_name },
          { name = "RABBITMQ_URL",   value = var.rabbitmq_url }
        ],
        each.key == "api_gateway" ? [
          { name = "ORDER_SERVICE_URL",        value = "http://${var.order_service_ip}:8000" },
          { name = "INVENTORY_SERVICE_URL",    value = "http://${var.inventory_service_ip}:8000" },
          { name = "PAYMENT_SERVICE_URL",      value = "http://${var.payment_service_ip}:8000" },
          { name = "NOTIFICATION_SERVICE_URL", value = "http://${var.notification_service_ip}:8000" }
        ] : []
      )
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/order-system/${each.key}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
  tags = { Project = "lista6" }
}

resource "aws_lb" "main" {
  name               = "order-system-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  tags = { Name = "order-system-alb", Project = "lista6" }
}

resource "aws_lb_target_group" "api_gateway" {
  name        = "order-system-api-gateway-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }
  tags = { Project = "lista6" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_gateway.arn
  }
}

resource "aws_ecs_service" "services" {
  for_each = local.service_ports

  name            = "order-system-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.services[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = true
  }

  dynamic "load_balancer" {
    for_each = each.key == "api_gateway" ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.api_gateway.arn
      container_name   = each.key
      container_port   = each.value
    }
  }

  depends_on = [aws_lb_listener.http]
  tags = { Project = "lista6" }
}