resource "aws_ecs_cluster" "scanner" {
  name = "${var.project_name}-${var.environment}-cluster"
}

resource "aws_security_group" "scanner_tasks" {
  name        = "${var.project_name}-${var.environment}-scanner-tasks"
  description = "Outbound-only security group for scanner Fargate tasks"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-scanner-tasks-sg"
  }
}

resource "aws_ecs_task_definition" "scanner" {
  family                   = "${var.project_name}-${var.environment}-scanner"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.scanner_cpu)
  memory                   = tostring(var.scanner_memory)
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  container_definitions = jsonencode([
    {
      name      = "scanner"
      image     = var.scanner_container_image
      essential = true
      environment = [
        {
          name  = "REPORT_BUCKET"
          value = aws_s3_bucket.reports.bucket
        },
        {
          name  = "METRICS_NAMESPACE"
          value = var.metrics_namespace
        },
        {
          name  = "PROJECT_NAME"
          value = var.project_name
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_scanner.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "scanner"
        }
      }
    }
  ])
}
