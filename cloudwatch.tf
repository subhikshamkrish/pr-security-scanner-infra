resource "aws_cloudwatch_log_group" "trigger_lambda" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-trigger"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "comparison_lambda" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-comparison"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "cleanup_lambda" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-cleanup"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "ecs_scanner" {
  name              = "/aws/ecs/${var.project_name}-${var.environment}-scanner"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "stepfunctions" {
  name              = "/aws/states/${var.project_name}-${var.environment}-workflow"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_metric_alarm" "ecs_scanner_high_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-scanner-high-cpu"
  alarm_description   = "Scanner ECS task CPU utilization exceeded ${var.scanner_cpu_alarm_threshold}%."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.scanner_cpu_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.scanner.name
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_scanner_high_memory" {
  alarm_name          = "${var.project_name}-${var.environment}-scanner-high-memory"
  alarm_description   = "Scanner ECS task memory utilization exceeded ${var.scanner_memory_alarm_threshold}%."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.scanner_memory_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.scanner.name
  }
}

resource "aws_cloudwatch_dashboard" "scanner" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# Differential PR Security Scanner\nMonitor workflow status, Lambda health, ECS scanner CPU/memory, and scanner logs."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title   = "Step Functions Executions"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", aws_sfn_state_machine.scanner_workflow.arn],
            [".", "ExecutionsSucceeded", ".", "."],
            [".", "ExecutionsFailed", ".", "."],
            [".", "ExecutionsTimedOut", ".", "."],
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title   = "Step Functions Duration"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/States", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.scanner_workflow.arn],
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Errors"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.trigger.function_name],
            [".", ".", ".", aws_lambda_function.comparison.function_name],
            [".", ".", ".", aws_lambda_function.cleanup.function_name],
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Duration"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.trigger.function_name],
            [".", ".", ".", aws_lambda_function.comparison.function_name],
            [".", ".", ".", aws_lambda_function.cleanup.function_name],
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 12
        height = 6
        properties = {
          title   = "ECS Scanner CPU Utilization"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.scanner.name],
          ]
          annotations = {
            horizontal = [
              {
                label = "CPU alarm threshold"
                value = var.scanner_cpu_alarm_threshold
              }
            ]
          }
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 14
        width  = 12
        height = 6
        properties = {
          title   = "ECS Scanner Memory Utilization"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.scanner.name],
          ]
          annotations = {
            horizontal = [
              {
                label = "Memory alarm threshold"
                value = var.scanner_memory_alarm_threshold
              }
            ]
          }
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 20
        width  = 24
        height = 8
        properties = {
          title  = "Recent Scanner Logs"
          region = var.aws_region
          query  = "SOURCE '${aws_cloudwatch_log_group.ecs_scanner.name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
        }
      }
    ]
  })
}
