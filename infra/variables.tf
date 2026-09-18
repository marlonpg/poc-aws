variable "aws_region" {
  description = "AWS region the POC runs in"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag all resources"
  type        = string
  default     = "pocaws"
}

variable "instance_id" {
  description = "ID of the existing, manually-created EC2 instance (not managed by Terraform)"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR allowed to reach the API on port 8080 (your own IP, e.g. 1.2.3.4/32)"
  type        = string
}

variable "app_port" {
  description = "Port the app on the EC2 instance listens on"
  type        = number
  default     = 8080
}

variable "github_org" {
  description = "GitHub org/user that owns the deploy repo"
  type        = string
  default     = "marlonpg"
}

variable "github_repo" {
  description = "GitHub repo name allowed to assume the deploy role via OIDC"
  type        = string
  default     = "poc-aws"
}

variable "artifact_retention_days" {
  description = "Days to retain old jar versions in the S3 artifact bucket"
  type        = number
  default     = 14
}
