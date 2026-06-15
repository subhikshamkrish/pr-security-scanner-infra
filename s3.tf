locals {
  name_prefix = "${var.project_name}-${var.environment}"

  bucket_name = lower(
    substr(
      replace(
        "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-reports",
        "_",
        "-"
      ),
      0,
      63
    )
  )
}

resource "aws_s3_bucket" "reports" {
  bucket = local.bucket_name

  tags = {
    Name = local.bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
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

resource "aws_s3_bucket_website_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_object" "dashboard_index" {
  bucket       = aws_s3_bucket.reports.bucket
  key          = "index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/index.html")
}

resource "aws_s3_bucket_policy" "reports_website" {
  bucket = aws_s3_bucket.reports.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "PublicReadDashboard"
        Effect = "Allow"

        Principal = "*"

        Action = [
          "s3:GetObject"
        ]

        Resource = [
          "${aws_s3_bucket.reports.arn}/index.html",
          "${aws_s3_bucket.reports.arn}/*.json",
          "${aws_s3_bucket.reports.arn}/reports/*"
        ]
      }
    ]
  })
}

output "dashboard_url" {
  value = "http://${aws_s3_bucket.reports.bucket}.s3-website-${data.aws_region.current.name}.amazonaws.com"
}