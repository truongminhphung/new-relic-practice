resource "aws_ssm_parameter" "nr_license_key" {
  name  = "/${local.name}/nr-license-key"
  type  = "SecureString"
  value = var.new_relic_license_key
  tags  = local.tags
}
