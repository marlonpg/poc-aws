resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-old-artifact-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.artifact_retention_days
    }
  }
}

# The 3 services' app.py, uploaded by Terraform itself (etag = content hash,
# so `terraform apply` re-uploads automatically whenever the file changes -
# no separate `aws s3 cp` step needed). The instance pulls these at first
# boot via user_data (infra/ec2_instance.tf) and on every later redeploy
# via each service's own deploy.sh (RUN.md).
resource "aws_s3_object" "orchestrator_app" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "demo-orchestrator/app.py"
  source = "${path.module}/../demo-orchestrator/app.py"
  etag   = filemd5("${path.module}/../demo-orchestrator/app.py")
}

resource "aws_s3_object" "app_app" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "demo-app/app.py"
  source = "${path.module}/../demo-app/app.py"
  etag   = filemd5("${path.module}/../demo-app/app.py")
}

resource "aws_s3_object" "db_app" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "demo-app-db/app.py"
  source = "${path.module}/../demo-app-db/app.py"
  etag   = filemd5("${path.module}/../demo-app-db/app.py")
}
