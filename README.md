# Differential PR Security Scanner Infrastructure

Terraform infrastructure for the CS6620 cloud project.

Components:
- VPC
- ECS Fargate
- Lambda
- Step Functions
- S3
- CloudWatch
- IAM

This version is designed for AWS Learner Lab and uses the pre-created `LabRole`
and `LabInstanceProfile` instead of creating custom IAM resources.

GitHub sends pull request webhooks to API Gateway. API Gateway invokes the
trigger Lambda, which validates the GitHub signature and starts the Step
Functions workflow. Step Functions handles cache decisions, ECS scans,
comparison, and cleanup.

## GitHub Webhook Setup

Set the webhook secret at apply time. Do not commit the secret to
`terraform.tfvars`.

```powershell
$env:TF_VAR_github_webhook_secret = "<random-webhook-secret>"
.\terraform apply
.\terraform output github_webhook_url
```

In the demo GitHub repository, create a webhook:

- Payload URL: value from `github_webhook_url`
- Content type: `application/json`
- Secret: same value as `TF_VAR_github_webhook_secret`
- Events: Pull requests
- Active: checked

The normal PR trigger no longer needs AWS access keys in GitHub Actions. The
current scanner downloads public GitHub commit archives directly inside ECS. For
private repositories, add a GitHub App or short-lived token flow before using
the direct archive download design.

## Scanner Container

The ECS task expects a Semgrep-based scanner image. Build and push the image in
`scanner/`, then set `scanner_container_image` in `terraform.tfvars`.

Example Docker Hub flow:

```powershell
cd "D:\Cloud Project\pr-security-scanner-infra\scanner"
docker build -t <dockerhub-user>/pr-security-scanner-semgrep:latest .
docker push <dockerhub-user>/pr-security-scanner-semgrep:latest
```

Then set:

```hcl
scanner_container_image = "<dockerhub-user>/pr-security-scanner-semgrep:latest"
```
