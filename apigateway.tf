resource "aws_apigatewayv2_api" "github_webhook" {
  name          = "${var.project_name}-${var.environment}-github-webhook"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "github_webhook" {
  api_id                 = aws_apigatewayv2_api.github_webhook.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.trigger.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "github_webhook" {
  api_id    = aws_apigatewayv2_api.github_webhook.id
  route_key = "POST /github/webhook"
  target    = "integrations/${aws_apigatewayv2_integration.github_webhook.id}"
}

resource "aws_apigatewayv2_stage" "github_webhook" {
  api_id      = aws_apigatewayv2_api.github_webhook.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_api_gateway_trigger" {
  statement_id  = "AllowGithubWebhookApiInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.github_webhook.execution_arn}/*/*"
}
