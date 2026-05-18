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

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  service_ports = {
    api_gateway          = 8000
    order_service        = 8001
    inventory_service    = 8002
    payment_service      = 8003
    notification_service = 8004
  }

  db_names = {
    api_gateway          = "gateway_db"
    order_service        = "orders_db"
    inventory_service    = "inventory_db"
    payment_service      = "payment_db"
    notification_service = null
  }

  db_urls = {
    for svc, db in local.db_names :
    svc => db != null
      ? "postgresql+asyncpg://${var.db_username}:${var.db_password}@${var.rds_host}/${db}?ssl=require"
      : "dynamodb"
  }

  base_environment = [
    { name = "AWS_REGION", value = var.aws_region },
    { name = "S3_BUCKET_NAME", value = var.s3_bucket_name },
    { name = "RABBITMQ_URL", value = var.rabbitmq_url },
  ]

  api_gateway_extra_env = [
    { name = "ORDER_SERVICE_URL", value = var.order_service_url },
    { name = "INVENTORY_SERVICE_URL", value = var.inventory_service_url },
    { name = "PAYMENT_SERVICE_URL", value = var.payment_service_url },
    { name = "NOTIFICATION_SERVICE_URL", value = var.notification_service_url },
  ]

  service_environment = {
    for svc in var.service_names :
    svc => concat(
      local.base_environment,
      [{ name = "DATABASE_URL", value = local.db_urls[svc] }],
      svc == "api_gateway" ? local.api_gateway_extra_env : []
    )
  }
}

# ── IAM ───────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "ecs_execution" {
  name = "order-system-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = "lista6"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "order-system-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = "lista6"
  }
}

resource "aws_iam_role_policy" "ecs_task_inline" {
  name = "order-system-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}"
      },
    ]
  })
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "services" {
  for_each = toset(var.service_names)

  name              = "/ecs/order-system/${each.key}"
  retention_in_days = 7

  tags = {
    Project = "lista6"
  }
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "order-system-cluster"

  tags = {
    Project = "lista6"
  }
}

# ── ECS Task Definitions ──────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "services" {
  for_each = toset(var.service_names)

  family                   = "order-system-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = each.key
    image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/order-system-${each.key}:latest"
    essential = true

    portMappings = [{
      containerPort = local.service_ports[each.key]
      protocol      = "tcp"
    }]

    environment = local.service_environment[each.key]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/order-system/${each.key}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = {
    Project = "lista6"
  }
}

# ── Application Load Balancer ─────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "order-system-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  tags = {
    Project = "lista6"
  }
}

resource "aws_lb_target_group" "api_gateway" {
  name        = "order-system-api-gateway-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = {
    Project = "lista6"
  }
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

# ── ECS Services ──────────────────────────────────────────────────────────────

resource "aws_ecs_service" "services" {
  for_each = toset(var.service_names)

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
      container_port   = local.service_ports[each.key]
    }
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.ecs_execution,
  ]

  tags = {
    Project = "lista6"
  }
}
