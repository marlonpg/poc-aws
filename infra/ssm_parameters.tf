# CloudWatch agent config as a Terraform-managed SSM Parameter (the AWS-
# documented way to manage this at scale) instead of a hand-written JSON
# file baked into a shell script. The instance pulls it via
# `amazon-cloudwatch-agent-ctl -c ssm:<name>` (demo-common/bootstrap-common.sh).
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name = "/${var.project_name}/cloudwatch-agent-config"
  type = "String"
  tags = local.common_tags

  value = jsonencode({
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path       = "/opt/pocaws-orchestrator/app.log"
              log_group_name  = aws_cloudwatch_log_group.demo_orchestrator.name
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/opt/pocaws-demo/app.log"
              log_group_name  = aws_cloudwatch_log_group.demo_app.name
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/opt/pocaws-demo-db/app.log"
              log_group_name  = aws_cloudwatch_log_group.demo_app_db.name
              log_stream_name = "{instance_id}"
            }
          ]
        }
      }
    }
  })
}
