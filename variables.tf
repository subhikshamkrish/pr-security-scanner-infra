variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "pr-security-scanner"
}

variable "environment" {
  type    = string
  default = "learner-lab"
}

variable "lab_role_name" {
  type    = string
  default = "LabRole"
}

variable "lab_instance_profile_name" {
  type    = string
  default = "LabInstanceProfile"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "input_zip_retention_days" {
  type    = number
  default = 1
}

variable "scan_report_retention_days" {
  type    = number
  default = 30
}

variable "diff_report_retention_days" {
  type    = number
  default = 30
}

variable "lambda_runtime" {
  type    = string
  default = "python3.12"
}

variable "lambda_timeout_seconds" {
  type    = number
  default = 30
}

variable "scanner_container_image" {
  type    = string
  default = "semgrep/semgrep:latest"
}

variable "scanner_cpu" {
  type    = number
  default = 256
}

variable "scanner_memory" {
  type    = number
  default = 512
}

variable "scanner_cpu_alarm_threshold" {
  type    = number
  default = 80
}

variable "scanner_memory_alarm_threshold" {
  type    = number
  default = 80
}

variable "common_tags" {
  type = map(string)
  default = {
    Course    = "CS6620"
    ManagedBy = "Terraform"
  }
}
