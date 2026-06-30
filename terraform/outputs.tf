output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.etl.arn
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.etl.name
}

output "scheduler_name" {
  value = aws_scheduler_schedule.etl_daily.name
}

output "manual_run_command" {
  description = "Run the ETL task on demand without waiting for the schedule."
  value       = <<-EOT
    aws ecs run-task \
      --region ${var.aws_region} \
      --cluster ${aws_ecs_cluster.this.name} \
      --task-definition ${aws_ecs_task_definition.etl.family} \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[${join(",", aws_subnet.public[*].id)}],securityGroups=[${aws_security_group.ecs.id}],assignPublicIp=ENABLED}"
  EOT
}
