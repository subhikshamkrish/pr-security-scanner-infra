locals {
  name_prefix = "${var.project_name}-${var.environment}"
  bucket_name = lower(substr(replace("${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-reports", "_", "-"), 0, 63))
}

resource "aws_s3_bucket" "reports" {
  bucket = local.bucket_name

  tags = {
    Name = local.bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "expire-temporary-input-zips"
    status = "Enabled"

    filter {
      prefix = "inputs/"
    }

    expiration {
      days = var.input_zip_retention_days
    }
  }

  rule {
    id     = "expire-scan-reports"
    status = "Enabled"

    filter {
      prefix = "reports/scans/"
    }

    expiration {
      days = var.scan_report_retention_days
    }
  }

  rule {
    id     = "expire-diff-reports"
    status = "Enabled"

    filter {
      prefix = "reports/diff/"
    }

    expiration {
      days = var.diff_report_retention_days
    }
  }
}
