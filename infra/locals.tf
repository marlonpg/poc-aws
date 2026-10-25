data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}
