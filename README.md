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

GitHub Actions should invoke the trigger Lambda, which starts the Step Functions
workflow. Step Functions handles cache decisions, ECS scans, comparison, and
temporary input cleanup.

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
