# The EC2 instance itself is pre-existing and NOT managed by Terraform (see
# README.md). We look it up read-only just to place the new SG in the right
# VPC — this data source never causes Terraform to modify the instance.
data "aws_instance" "app" {
  instance_id = var.instance_id
}

data "aws_subnet" "app" {
  id = data.aws_instance.app.subnet_id
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app"
  description = "poc-aws app SG: API port from admin IP only, no SSH (SSM used instead)"
  vpc_id      = data.aws_subnet.app.vpc_id

  ingress {
    description = "API access from admin IP"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "Allow all outbound (SSM agent, S3, package manager)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-app"
  })
}
