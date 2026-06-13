output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.main.id
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "reports_bucket_name" {
  value = aws_s3_bucket.reports.bucket
}

output "reports_bucket_arn" {
  value = aws_s3_bucket.reports.arn
}

output "lab_role_arn" {
  value = data.aws_iam_role.lab_role.arn
}

output "lab_instance_profile_arn" {
  value = data.aws_iam_instance_profile.lab_instance_profile.arn
}

output "trigger_lambda_arn" {
  value = aws_lambda_function.trigger.arn
}

output "comparison_lambda_arn" {
  value = aws_lambda_function.comparison.arn
}

output "cleanup_lambda_arn" {
  value = aws_lambda_function.cleanup.arn
}

output "trigger_lambda_name" {
  value = aws_lambda_function.trigger.function_name
}

output "github_webhook_url" {
  value = "${aws_apigatewayv2_api.github_webhook.api_endpoint}/github/webhook"
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.scanner.arn
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.scanner.arn
}

output "scanner_workflow_arn" {
  value = aws_sfn_state_machine.scanner_workflow.arn
}
