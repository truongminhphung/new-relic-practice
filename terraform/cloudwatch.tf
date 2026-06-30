resource "aws_cloudwatch_log_group" "etl" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}
