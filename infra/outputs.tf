output "security_group_id" {
  value = aws_security_group.app.id
}

output "instance_id" {
  value = aws_instance.app.id
}

output "instance_public_ip" {
  value = aws_instance.app.public_ip
}

output "demo_orchestrator_log_group" {
  value = aws_cloudwatch_log_group.demo_orchestrator.name
}

output "demo_app_log_group" {
  value = aws_cloudwatch_log_group.demo_app.name
}

output "demo_app_db_log_group" {
  value = aws_cloudwatch_log_group.demo_app_db.name
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.demo.dashboard_name}"
}

output "artifact_bucket_name" {
  value = aws_s3_bucket.artifacts.id
}

output "cloudtrail_bucket_name" {
  value = aws_s3_bucket.cloudtrail_logs.id
}
