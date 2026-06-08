data "archive_file" "trigger_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/trigger"
  output_path = "${path.module}/trigger_lambda.zip"
}

data "archive_file" "comparison_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/comparison"
  output_path = "${path.module}/comparison_lambda.zip"
}

data "archive_file" "cleanup_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/cleanup"
  output_path = "${path.module}/cleanup_lambda.zip"
}

resource "aws_lambda_function" "trigger" {
  function_name    = "${var.project_name}-${var.environment}-trigger"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "lambda_function.handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.trigger_lambda.output_path
  source_code_hash = data.archive_file.trigger_lambda.output_base64sha256
  timeout          = var.lambda_timeout_seconds

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.scanner_workflow.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.trigger_lambda]
}

resource "aws_lambda_function" "comparison" {
  function_name    = "${var.project_name}-${var.environment}-comparison"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "lambda_function.handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.comparison_lambda.output_path
  source_code_hash = data.archive_file.comparison_lambda.output_base64sha256
  timeout          = var.lambda_timeout_seconds

  environment {
    variables = {
      REPORT_BUCKET = aws_s3_bucket.reports.bucket
    }
  }

  depends_on = [aws_cloudwatch_log_group.comparison_lambda]
}

resource "aws_lambda_function" "cleanup" {
  function_name    = "${var.project_name}-${var.environment}-cleanup"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "lambda_function.handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.cleanup_lambda.output_path
  source_code_hash = data.archive_file.cleanup_lambda.output_base64sha256
  timeout          = var.lambda_timeout_seconds

  environment {
    variables = {
      REPORT_BUCKET = aws_s3_bucket.reports.bucket
    }
  }

  depends_on = [aws_cloudwatch_log_group.cleanup_lambda]
}
