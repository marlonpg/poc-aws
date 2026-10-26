# The instance, fully Terraform-managed (unlike the earlier hand-created
# one - see git history / infra/README.md for why that was the case
# before). AMI, VPC/subnet, security group, IAM profile, and first-boot
# config are all declared here; nothing about this instance needs a manual
# console or CLI step anymore.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    # The "standard" AMI (name starts "al2023-ami-2023...") ships with the
    # SSM Agent, CloudWatch agent CLI tools, and AWS CLI preinstalled. The
    # "al2023-ami-minimal-*" variant does NOT include the SSM Agent, which
    # breaks every SSM-based redeploy in this project - exclude it
    # explicitly rather than relying on a loose wildcard.
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  # us-east-1e (among the default VPC's subnets) doesn't support t3.micro -
  # pin to an AZ that does, rather than letting Terraform pick arbitrarily.
  filter {
    name   = "availability-zone"
    values = ["us-east-1a"]
  }
}

locals {
  # First-boot provisioning: the exact same scripts used for manual
  # redeploys (RUN.md), just concatenated with file() (not templatefile() -
  # these scripts use bash's own ${VAR} expansion throughout, which would
  # collide with Terraform's template syntax; file() reads them as raw
  # text with zero interpretation, so nothing needs escaping). The only
  # Terraform-side values injected are the two `export` lines each
  # deploy.sh expects.
  user_data = join("\n", [
    "#!/bin/bash",
    "set -euo pipefail",
    file("${path.module}/../demo-common/bootstrap-common.sh"),
    "export S3_BUCKET=${aws_s3_bucket.artifacts.id}",
    "export S3_KEY=demo-app-db/app.py",
    file("${path.module}/../demo-app-db/deploy.sh"),
    "export S3_KEY=demo-app/app.py",
    file("${path.module}/../demo-app/deploy.sh"),
    "export S3_KEY=demo-orchestrator/app.py",
    file("${path.module}/../demo-orchestrator/deploy.sh"),
  ])
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = true
  user_data                   = local.user_data
  # Any user_data change (e.g. editing bootstrap-common.sh) replaces the
  # instance - this is a POC, immutable-style replace is simpler and safer
  # than trying to re-run cloud-init on an existing instance.
  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name          = "${var.project_name}-app"
    "Patch Group" = "${var.project_name}-patch-group"
  })

  depends_on = [
    aws_s3_object.orchestrator_app,
    aws_s3_object.app_app,
    aws_s3_object.db_app,
    aws_ssm_parameter.cloudwatch_agent_config,
  ]
}
