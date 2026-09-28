output "security_group_id" {
  value = aws_security_group.app.id
}

output "instance_public_ip" {
  value = data.aws_instance.app.public_ip
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

output "instance_profile_name" {
  value = aws_iam_instance_profile.app.name
}

output "artifact_bucket_name" {
  value = aws_s3_bucket.artifacts.id
}

output "gha_deploy_role_arn" {
  value = aws_iam_role.gha_deploy.arn
}

output "cloudtrail_bucket_name" {
  value = aws_s3_bucket.cloudtrail_logs.id
}

output "patch_group_tag_value" {
  value       = "${var.project_name}-patch-group"
  description = "Tag the existing instance with key 'Patch Group' and this value to enroll it in patching"
}
