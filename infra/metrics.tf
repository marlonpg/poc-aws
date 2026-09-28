# Turns the "ERROR: ..." log line each service already prints into a
# CloudWatch metric, one per tier, so a spike is visible on a graph and can
# drive an alarm - no code change needed, just reading the existing logs.

resource "aws_cloudwatch_log_metric_filter" "orchestrator_errors" {
  name           = "${var.project_name}-orchestrator-errors"
  log_group_name = aws_cloudwatch_log_group.demo_orchestrator.name
  pattern        = "ERROR"

  metric_transformation {
    name          = "OrchestratorErrorCount"
    namespace     = "PocAwsDemo"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "${var.project_name}-app-errors"
  log_group_name = aws_cloudwatch_log_group.demo_app.name
  pattern        = "ERROR"

  metric_transformation {
    name          = "AppErrorCount"
    namespace     = "PocAwsDemo"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "db_errors" {
  name           = "${var.project_name}-db-errors"
  log_group_name = aws_cloudwatch_log_group.demo_app_db.name
  pattern        = "ERROR"

  metric_transformation {
    name          = "DbErrorCount"
    namespace     = "PocAwsDemo"
    value         = "1"
    default_value = "0"
  }
}

# The DB tier is the actual root cause in this scenario, so it's the one
# wired to an alarm - the other two metrics are there to show they stay
# quiet while only the DB tier's error count spikes.
resource "aws_cloudwatch_metric_alarm" "db_errors" {
  alarm_name          = "${var.project_name}-db-errors"
  alarm_description   = "demo-app-db is returning errors (simulated DB failure)"
  namespace           = "PocAwsDemo"
  metric_name         = "DbErrorCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  tags                = local.common_tags
}
