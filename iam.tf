data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_role" "lab_role" {
  name = var.lab_role_name
}

data "aws_iam_instance_profile" "lab_instance_profile" {
  name = var.lab_instance_profile_name
}
