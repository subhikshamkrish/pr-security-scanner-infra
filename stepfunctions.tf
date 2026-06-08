resource "aws_sfn_state_machine" "scanner_workflow" {
  name     = "${var.project_name}-${var.environment}-workflow"
  role_arn = data.aws_iam_role.lab_role.arn
  type     = "STANDARD"

  logging_configuration {
    include_execution_data = true
    level                  = "ALL"
    log_destination        = "${aws_cloudwatch_log_group.stepfunctions.arn}:*"
  }

  definition = jsonencode({
    Comment = "Differential PR Security Scanner orchestration"
    StartAt = "RunScansInParallel"
    States = {
      RunScansInParallel = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "CheckBaseScanCache"
            States = {
              CheckBaseScanCache = {
                Type = "Choice"
                Choices = [
                  {
                    Variable      = "$.base.report_exists"
                    BooleanEquals = true
                    Next          = "UseCachedBaseReport"
                  }
                ]
                Default = "BaseScan"
              }
              UseCachedBaseReport = {
                Type = "Pass"
                Parameters = {
                  scan_kind      = "base"
                  cache_hit      = true
                  "report_key.$" = "$.base.report_key"
                }
                End = true
              }
              BaseScan = {
                Type     = "Task"
                Resource = "arn:aws:states:::ecs:runTask.sync"
                Parameters = {
                  Cluster        = aws_ecs_cluster.scanner.arn
                  TaskDefinition = aws_ecs_task_definition.scanner.arn
                  LaunchType     = "FARGATE"
                  NetworkConfiguration = {
                    AwsvpcConfiguration = {
                      Subnets        = [aws_subnet.private.id]
                      SecurityGroups = [aws_security_group.scanner_tasks.id]
                      AssignPublicIp = "DISABLED"
                    }
                  }
                  Overrides = {
                    ContainerOverrides = [
                      {
                        Name = "scanner"
                        Environment = [
                          {
                            Name  = "SCAN_KIND"
                            Value = "base"
                          },
                          {
                            Name  = "REPORT_BUCKET"
                            Value = aws_s3_bucket.reports.bucket
                          },
                          {
                            Name      = "INPUT_ZIP_KEY"
                            "Value.$" = "$.base.zip_key"
                          },
                          {
                            Name      = "REPORT_KEY"
                            "Value.$" = "$.base.report_key"
                          }
                        ]
                      }
                    ]
                  }
                }
                Retry = [
                  {
                    ErrorEquals     = ["States.ALL"]
                    IntervalSeconds = 2
                    MaxAttempts     = 3
                    BackoffRate     = 2
                  }
                ]
                End = true
              }
            }
          },
          {
            StartAt = "CheckPrScanCache"
            States = {
              CheckPrScanCache = {
                Type = "Choice"
                Choices = [
                  {
                    Variable      = "$.pr.report_exists"
                    BooleanEquals = true
                    Next          = "UseCachedPrReport"
                  }
                ]
                Default = "PrScan"
              }
              UseCachedPrReport = {
                Type = "Pass"
                Parameters = {
                  scan_kind      = "pr"
                  cache_hit      = true
                  "report_key.$" = "$.pr.report_key"
                }
                End = true
              }
              PrScan = {
                Type     = "Task"
                Resource = "arn:aws:states:::ecs:runTask.sync"
                Parameters = {
                  Cluster        = aws_ecs_cluster.scanner.arn
                  TaskDefinition = aws_ecs_task_definition.scanner.arn
                  LaunchType     = "FARGATE"
                  NetworkConfiguration = {
                    AwsvpcConfiguration = {
                      Subnets        = [aws_subnet.private.id]
                      SecurityGroups = [aws_security_group.scanner_tasks.id]
                      AssignPublicIp = "DISABLED"
                    }
                  }
                  Overrides = {
                    ContainerOverrides = [
                      {
                        Name = "scanner"
                        Environment = [
                          {
                            Name  = "SCAN_KIND"
                            Value = "pr"
                          },
                          {
                            Name  = "REPORT_BUCKET"
                            Value = aws_s3_bucket.reports.bucket
                          },
                          {
                            Name      = "INPUT_ZIP_KEY"
                            "Value.$" = "$.pr.zip_key"
                          },
                          {
                            Name      = "REPORT_KEY"
                            "Value.$" = "$.pr.report_key"
                          }
                        ]
                      }
                    ]
                  }
                }
                Retry = [
                  {
                    ErrorEquals     = ["States.ALL"]
                    IntervalSeconds = 2
                    MaxAttempts     = 3
                    BackoffRate     = 2
                  }
                ]
                End = true
              }
            }
          }
        ]
        ResultPath = "$.scan_results"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "CleanupAfterFailure"
          }
        ]
        Next = "RunComparison"
      }
      RunComparison = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.comparison.arn
          Payload = {
            action              = "compare"
            report_bucket       = aws_s3_bucket.reports.bucket
            "repository.$"      = "$.repository"
            "base_report_key.$" = "$.base.report_key"
            "pr_report_key.$"   = "$.pr.report_key"
            "diff_report_key.$" = "$.diff_report_key"
            "execution_id.$"    = "$$.Execution.Id"
            "scan_results.$"    = "$.scan_results"
          }
        }
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 2
            MaxAttempts     = 2
            BackoffRate     = 2
          }
        ]
        ResultPath = "$.comparison"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "CleanupAfterFailure"
          }
        ]
        Next = "PostGithubCommentPlaceholder"
      }
      PostGithubCommentPlaceholder = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.comparison.arn
          Payload = {
            action              = "github_comment_placeholder"
            report_bucket       = aws_s3_bucket.reports.bucket
            "repository.$"      = "$.repository"
            "diff_report_key.$" = "$.diff_report_key"
            "comparison.$"      = "$.comparison.Payload"
          }
        }
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 2
            MaxAttempts     = 2
            BackoffRate     = 2
          }
        ]
        ResultPath = "$.github_comment"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "CleanupAfterFailure"
          }
        ]
        Next = "CleanupAfterSuccess"
      }
      CleanupAfterSuccess = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.cleanup.arn
          "Payload.$"  = "$"
        }
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 2
            MaxAttempts     = 2
            BackoffRate     = 2
          }
        ]
        ResultPath = "$.cleanup"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "WorkflowFailed"
          }
        ]
        Next = "WorkflowSucceeded"
      }
      CleanupAfterFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.cleanup.arn
          "Payload.$"  = "$"
        }
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 2
            MaxAttempts     = 2
            BackoffRate     = 2
          }
        ]
        ResultPath = "$.cleanup"
        Next       = "WorkflowFailed"
      }
      WorkflowSucceeded = {
        Type = "Succeed"
      }
      WorkflowFailed = {
        Type  = "Fail"
        Cause = "Differential PR Security Scanner workflow failed"
      }
    }
  })

  depends_on = [aws_cloudwatch_log_group.stepfunctions]
}
