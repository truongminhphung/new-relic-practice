# ── Zip the Lambda source ─────────────────────────────────────────────────────

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/forwarder.py"
  output_path = "${path.module}/../lambda/forwarder.zip"
}

# ── IAM role for the Lambda ───────────────────────────────────────────────────

resource "aws_iam_role" "nr_log_forwarder" {
  name = "${local.name}-nr-log-forwarder"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

# Grants permission to write Lambda's own execution logs to CloudWatch.
resource "aws_iam_role_policy_attachment" "nr_log_forwarder_basic" {
  role       = aws_iam_role.nr_log_forwarder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "nr_log_forwarder" {
  function_name    = "${local.name}-nr-log-forwarder"
  role             = aws_iam_role.nr_log_forwarder.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "forwarder.handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      NEW_RELIC_LICENSE_KEY = aws_ssm_parameter.nr_license_key.value
    }
  }

  tags = local.tags
}

# ── Allow CloudWatch Logs to invoke the Lambda ────────────────────────────────

resource "aws_lambda_permission" "allow_cloudwatch_logs" {
  statement_id   = "AllowCloudWatchLogs"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.nr_log_forwarder.function_name
  principal      = "logs.${var.aws_region}.amazonaws.com"
  source_arn     = "${aws_cloudwatch_log_group.etl.arn}:*"
}

# ── Subscription filter: pipe /ecs/etl-job → Lambda ──────────────────────────

resource "aws_cloudwatch_log_subscription_filter" "nr_forwarder" {
  name            = "nr-log-forwarder"
  log_group_name  = aws_cloudwatch_log_group.etl.name
  filter_pattern  = ""   # forward all log events
  destination_arn = aws_lambda_function.nr_log_forwarder.arn
  depends_on      = [aws_lambda_permission.allow_cloudwatch_logs]
}
