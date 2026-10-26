# counts side by side, the DB-tier alarm, and a live table of the actual
# error lines - shortcut for Metrics/Alarms/Logs pages
resource "aws_cloudwatch_dashboard" "demo" {
  dashboard_name = "${var.project_name}-demo"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 16
        height = 6
        properties = {
          title  = "Error count by tier (which service is the culprit?)"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          view   = "timeSeries"
          metrics = [
            ["PocAwsDemo", "OrchestratorErrorCount"],
            ["PocAwsDemo", "AppErrorCount"],
            ["PocAwsDemo", "DbErrorCount"]
          ]
        }
      },
      {
        type   = "alarm"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "DB tier alarm"
          alarms = [aws_cloudwatch_metric_alarm.db_errors.arn]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          title  = "demo-app-db: recent ERROR lines (root cause)"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.demo_app_db.name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
        }
      }
    ]
  })
}
