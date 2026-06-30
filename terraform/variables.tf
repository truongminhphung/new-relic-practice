variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "dockerhub_username" {
  type    = string
  default = "truongminhphungdocker"
}

variable "image_tag" {
  type    = string
  default = "latest"
  description = "Docker image tag to deploy. Override with a commit SHA to pin a specific build."
}

variable "new_relic_license_key" {
  type      = string
  sensitive = true
  description = "New Relic ingest license key. Pass via TF_VAR_new_relic_license_key — never commit."
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "schedule_expression" {
  type    = string
  default = "cron(0 10 * * ? *)"
  description = "EventBridge Scheduler cron expression. Default: 10:00 AM UTC daily."
}
