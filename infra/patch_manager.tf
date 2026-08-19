resource "aws_ssm_patch_group" "app" {
  baseline_id = data.aws_ssm_patch_baseline.al2023_default.id
  patch_group = "${var.project_name}-patch-group"
}

data "aws_ssm_patch_baseline" "al2023_default" {
  owner            = "AWS"
  name_prefix      = "AWS-AmazonLinux2023DefaultPatchBaseline"
  operating_system = "AMAZON_LINUX_2023"
}

resource "aws_iam_role" "maintenance_window" {
  name = "${var.project_name}-maintenance-window-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ssm.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "maintenance_window" {
  role       = aws_iam_role.maintenance_window.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}

resource "aws_ssm_maintenance_window" "patching" {
  name     = "${var.project_name}-patch-window"
  schedule = "cron(0 3 ? * SUN *)" # Sundays 03:00 UTC
  duration = 3
  cutoff   = 1
  tags     = local.common_tags
}

resource "aws_ssm_maintenance_window_target" "patching" {
  window_id     = aws_ssm_maintenance_window.patching.id
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Patch Group"
    values = ["${var.project_name}-patch-group"]
  }
}

resource "aws_ssm_maintenance_window_task" "patching" {
  window_id        = aws_ssm_maintenance_window.patching.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.maintenance_window.arn
  max_concurrency  = "1"
  max_errors       = "1"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.patching.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
    }
  }
}
