resource "aws_cloudwatch_log_group" "trigger_lambda" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-trigger"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "comparison_lambda" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-comparison"
  retention_in_days = var.log_retention_days
}

/*
resource "aws_cloudwatch_log_group" "cleanup_lambda" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-cleanup"
  retention_in_days = var.log_retention_days
}
*/

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
            #            [".", ".", ".", aws_lambda_function.cleanup.function_name],
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
            #            [".", ".", ".", aws_lambda_function.cleanup.function_name],
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
        y      = 38
        width  = 24
        height = 8
        properties = {
          title  = "Recent Scanner Logs"
          region = var.aws_region
          query  = "SOURCE '${aws_cloudwatch_log_group.ecs_scanner.name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 20
        width  = 12
        height = 6
        properties = {
          title   = "Scan Completion Rate"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            [var.metrics_namespace, "ScanStarted", "Project", var.project_name, "ScanKind", "base", { id = "base_started", visible = false }],
            [".", "ScanStarted", ".", ".", ".", "pr", { id = "pr_started", visible = false }],
            [".", "ScanCompleted", ".", ".", ".", "base", { id = "base_completed", visible = false }],
            [".", "ScanCompleted", ".", ".", ".", "pr", { id = "pr_completed", visible = false }],
            [{ expression = "100*((base_completed+pr_completed)/(base_started+pr_started))", label = "Scan Completion Rate (%)", id = "scan_completion_rate" }],
          ]
          period = 300
          stat   = "Sum"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 20
        width  = 12
        height = 6
        properties = {
          title   = "Average Scan Duration"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            [var.metrics_namespace, "ScanDurationSeconds", "Project", var.project_name, "ScanKind", "base", { label = "Base Scan Duration" }],
            [".", "ScanDurationSeconds", ".", ".", ".", "pr", { label = "PR Scan Duration" }],
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 26
        width  = 12
        height = 6
        properties = {
          title   = "Base Scan Cache Hit Rate"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            [var.metrics_namespace, "BaseScanCacheCheck", { id = "cache_checks", visible = false }],
            [".", "BaseScanCacheHit", { id = "cache_hits", visible = false }],
            [{ expression = "100*(cache_hits/cache_checks)", label = "Base Cache Hit Rate (%)", id = "base_cache_hit_rate" }],
          ]
          period = 300
          stat   = "Sum"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 26
        width  = 12
        height = 6
        properties = {
          title   = "Parallel Scan Completion + PR Comment Success"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            [var.metrics_namespace, "WorkflowStarted", { id = "workflow_started", visible = false }],
            [".", "ParallelScanCompleted", { id = "parallel_completed", visible = false }],
            [".", "PRCommentAttempted", { id = "comment_attempted", visible = false }],
            [".", "PRCommentSucceeded", { id = "comment_succeeded", visible = false }],
            [{ expression = "100*(parallel_completed/workflow_started)", label = "Parallel Scan Completion Rate (%)", id = "parallel_completion_rate" }],
            [{ expression = "100*(comment_succeeded/comment_attempted)", label = "PR Comment Success Rate (%)", id = "pr_comment_success_rate" }],
          ]
          period = 300
          stat   = "Sum"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 32
        width  = 12
        height = 6
        properties = {
          title   = "Input Retrieval Success Rate"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            [var.metrics_namespace, "S3DownloadAttempted", "Project", var.project_name, "ScanKind", "base", { id = "base_download_attempted", visible = false }],
            [".", "S3DownloadAttempted", ".", ".", ".", "pr", { id = "pr_download_attempted", visible = false }],
            [".", "S3DownloadSucceeded", ".", ".", ".", "base", { id = "base_download_succeeded", visible = false }],
            [".", "S3DownloadSucceeded", ".", ".", ".", "pr", { id = "pr_download_succeeded", visible = false }],
            [".", "SourceDownloadAttempted", ".", ".", ".", "base", { id = "base_source_attempted", visible = false }],
            [".", "SourceDownloadAttempted", ".", ".", ".", "pr", { id = "pr_source_attempted", visible = false }],
            [".", "SourceDownloadSucceeded", ".", ".", ".", "base", { id = "base_source_succeeded", visible = false }],
            [".", "SourceDownloadSucceeded", ".", ".", ".", "pr", { id = "pr_source_succeeded", visible = false }],
            [{ expression = "100*((base_download_succeeded+pr_download_succeeded+base_source_succeeded+pr_source_succeeded)/(base_download_attempted+pr_download_attempted+base_source_attempted+pr_source_attempted))", label = "Input Retrieval Success Rate (%)", id = "input_retrieval_success_rate" }],
          ]
          period = 300
          stat   = "Sum"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 32
        width  = 12
        height = 6
        properties = {
          title   = "S3 Report Storage Success Rate"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            [var.metrics_namespace, "S3UploadAttempted", "Project", var.project_name, "ScanKind", "base", { id = "base_upload_attempted", visible = false }],
            [".", "S3UploadAttempted", ".", ".", ".", "pr", { id = "pr_upload_attempted", visible = false }],
            [".", "S3UploadSucceeded", ".", ".", ".", "base", { id = "base_upload_succeeded", visible = false }],
            [".", "S3UploadSucceeded", ".", ".", ".", "pr", { id = "pr_upload_succeeded", visible = false }],
            [var.metrics_namespace, "DiffReportWriteAttempted", { id = "diff_write_attempted", visible = false }],
            [".", "DiffReportWriteSucceeded", { id = "diff_write_succeeded", visible = false }],
            [{ expression = "100*((base_upload_succeeded+pr_upload_succeeded+diff_write_succeeded)/(base_upload_attempted+pr_upload_attempted+diff_write_attempted))", label = "S3 Storage Success Rate (%)", id = "s3_storage_success_rate" }],
          ]
          period = 300
          stat   = "Sum"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      }
    ]
  })
}
