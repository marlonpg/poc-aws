resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_cloudwatch_log_group" "demo_app" {
  name              = "/aws/ec2/demo-app"
  retention_in_days = 3
  tags              = local.common_tags
}
