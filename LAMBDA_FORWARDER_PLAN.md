# Migration: APM Agent → CloudWatch Lambda Forwarder for New Relic

**Status:** Plan (pending implementation)
**Date:** 2026-06-30

---

## 1. Problem with the Current APM Agent Approach

The ETL job is a short-lived ECS Fargate task. The New Relic .NET APM agent was designed for long-running services (web servers) and has two fundamental mismatches with this pattern:

| Problem | Detail |
|---|---|
| **Harvest cycle mismatch** | The agent buffers telemetry and flushes every 60 seconds. A short ETL run may finish before the first harvest cycle completes, dropping all logs. |
| **Unreliable flush-on-exit** | `NEW_RELIC_SEND_DATA_ON_EXIT=true` helps, but cold-start reconnect delays (~24–39 s) mean the current workaround requires a `Task.Delay(40s)` after the job finishes — adding 40 seconds of idle time to every run. |
| **Unnecessary overhead** | The agent adds ~40 MB to the image, extends startup time, and hooks the CoreCLR profiler — none of which is needed when the only goal is log forwarding. |

---

## 2. Solution: CloudWatch Logs → Lambda → New Relic

ECS already ships all stdout/stderr to CloudWatch Logs via the `awslogs` log driver. The new approach adds one AWS Lambda function that acts as a CloudWatch Logs subscriber: it triggers on every new log batch, transforms the payload, and POSTs directly to the New Relic Log API over HTTPS.

The ETL job itself stays unchanged — it just writes to stdout and exits immediately. The Lambda handles delivery asynchronously and reliably.

---

## 3. Architecture

### 3.1 Current (APM Agent)

```
ECS Fargate Task
  ┌──────────────────────────────────┐
  │  C# ETL app                      │
  │  + New Relic .NET APM agent      │  ──► New Relic APM (HTTPS, harvest cycle)
  │  + Task.Delay(40s) workaround    │
  └──────────────────────────────────┘
           │ stdout (awslogs)
           ▼
  CloudWatch Logs  (used only for CloudWatch, not NR)
```

### 3.2 New (Lambda Forwarder)

```
                    ┌──────────────────────────────────────────┐
  git push (main)   │           GitHub Actions                  │
 ─────────────────► │  dotnet build → docker build → push       │
                    │  (leaner image — NO NR agent baked in)    │
                    └───────────────────┬──────────────────────┘
                                        │ push image:tag
                                        ▼
                              ┌───────────────────┐
                              │     Docker Hub     │
                              │  (smaller image)   │
                              └─────────┬─────────┘
                                        │ pull at run time
                                        ▼
┌───────────────┐  cron(0 10 * * ? *)  ┌─────────────────────────────────────┐
│  EventBridge  │ ───────────────────► │        ECS Fargate Task              │
│  Scheduler    │                      │  ┌─────────────────────────────────┐ │
└───────────────┘                      │  │  C# ETL app (no NR agent)       │ │
                                       │  │  exits as soon as work is done ✓ │ │
                                       │  └──────────────┬──────────────────┘ │
                                       └─────────────────┼────────────────────┘
                                                         │ stdout/stderr
                                                         │ (awslogs driver — unchanged)
                                                         ▼
                                              ┌──────────────────────┐
                                              │   CloudWatch Logs    │
                                              │   /ecs/etl-job        │
                                              └──────────┬───────────┘
                                                         │ subscription filter
                                                         │ (triggers on every log batch)
                                                         ▼
                                              ┌──────────────────────┐
                                              │  Lambda Function      │
                                              │  newrelic-log-fwd     │
                                              │                       │
                                              │  • Decompress gzip    │
                                              │  • Parse log events   │
                                              │  • POST to NR Log API │
                                              └──────────┬───────────┘
                                                         │ HTTPS POST /log/v1
                                                         ▼
                                              ┌──────────────────────┐
                                              │    New Relic Logs    │
                                              │    + Dashboard        │
                                              └──────────────────────┘
```

---

## 4. What Changes vs What Stays the Same

### Removed (no longer needed)

| Item | Why removed |
|---|---|
| New Relic .NET APM agent install in `Dockerfile` | Logs now flow via CloudWatch → Lambda, not in-process agent |
| `CORECLR_*` profiler env vars in `Dockerfile` | No profiler to load |
| `NEW_RELIC_APPLICATION_LOGGING_*` env vars | Agent feature, no longer relevant |
| `NEW_RELIC_SEND_DATA_ON_EXIT*` env vars | No agent to flush |
| `await Task.Delay(TimeSpan.FromSeconds(40))` in `Program.cs` | Job can exit immediately |
| `NEW_RELIC_LICENSE_KEY` secret in ECS task definition | ECS no longer needs it; Lambda uses it |

### Added

| Item | Purpose |
|---|---|
| `terraform/lambda.tf` | Lambda function + IAM role + CloudWatch subscription filter |
| Lambda IAM execution role | Allow Lambda to write its own logs to CloudWatch |
| CloudWatch subscription filter | Pipe log events from `/ecs/etl-job` to the Lambda |
| Lambda permission for CloudWatch | Allow CloudWatch Logs service to invoke Lambda |

### Unchanged

| Item | Note |
|---|---|
| `awslogs` log driver in ECS task definition | Already configured — this is the source |
| CloudWatch Log Group `/ecs/etl-job` | Still the intermediary |
| EventBridge Scheduler | Cron schedule stays the same |
| VPC / networking / subnets | No change |
| GitHub Actions CI/CD | Workflow unchanged (image gets smaller, that's all) |
| `Microsoft.Extensions.Logging` in the app | Still writes structured logs to stdout |
| SSM Parameter Store for NR license key | Reused by Lambda instead of ECS |

---

## 5. Component Design

### 5.1 Lambda Function (Python)

The Lambda receives a CloudWatch Logs event (gzipped + base64-encoded), decodes it, and POSTs to New Relic's Log API.

```
CloudWatch Logs → subscription filter → Lambda (Python 3.12)
                                              │
                                              └── POST https://log-api.newrelic.com/log/v1
                                                  Header: X-License-Key: <from env>
                                                  Body:   [{
                                                            "common": { "attributes": { "logGroup": ..., "logStream": ... } },
                                                            "logs": [{ "timestamp": ..., "message": ... }]
                                                          }]
```

**Deployment approach — New Relic SAR (recommended):**

New Relic publishes and maintains an official Lambda function in the AWS Serverless Application Repository (SAR):
- ARN: `arn:aws:serverlessrepo:us-east-1:463657938898:applications/NewRelic-log-ingestion`
- Language: Python
- Maintained by New Relic; supports structured log parsing, filtering, and retry

This is deployed in Terraform via `aws_serverlessapplicationrepository_cloudformation_stack`.

**Alternative — inline Python Lambda:**

A compact Python function written inline in Terraform (no S3 zip, no external dependency) that implements the same HTTP POST. Useful if the SAR approach hits permissions issues in restricted AWS environments.

### 5.2 Dockerfile (after migration)

```dockerfile
# ---- build stage ----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY src/EtlJob/EtlJob.csproj ./EtlJob/
RUN dotnet restore ./EtlJob/EtlJob.csproj
COPY src/EtlJob/ ./EtlJob/
RUN dotnet publish ./EtlJob/EtlJob.csproj -c Release -o /app --no-restore

# ---- runtime stage (clean — no NR agent) ----
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS final
WORKDIR /app
COPY --from=build /app ./
ENTRYPOINT ["dotnet", "EtlJob.dll"]
```

Image size drops from ~700 MB to ~220 MB (no agent install layer).

### 5.3 Program.cs (after migration)

Remove the `Task.Delay` workaround — the job exits as soon as it finishes:

```csharp
// Before (with APM agent workaround):
await Task.Delay(TimeSpan.FromSeconds(40));
return 0;

// After (no workaround needed):
return 0;
```

### 5.4 Terraform: `lambda.tf` (new file)

```hcl
# ── IAM role for the Lambda ──────────────────────────────────────────────────
resource "aws_iam_role" "nr_log_forwarder" {
  name = "etl-job-nr-log-forwarder"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nr_log_forwarder_basic" {
  role       = aws_iam_role.nr_log_forwarder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Deploy NR log forwarder from Serverless Application Repository ────────────
resource "aws_serverlessapplicationrepository_cloudformation_stack" "nr_log_ingestion" {
  name             = "nr-log-ingestion"
  application_id   = "arn:aws:serverlessrepo:us-east-1:463657938898:applications/NewRelic-log-ingestion"
  semantic_version = "2.4.0"
  capabilities     = ["CAPABILITY_IAM"]

  parameters = {
    NRLicenseKey = aws_ssm_parameter.nr_license_key.value
    NRLoggingEnabled = "true"
  }
}

# ── Allow CloudWatch Logs to invoke the Lambda ────────────────────────────────
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id   = "AllowCloudWatchLogs"
  action         = "lambda:InvokeFunction"
  function_name  = aws_serverlessapplicationrepository_cloudformation_stack.nr_log_ingestion.outputs["NewRelicLogIngestionFunctionArn"]
  principal      = "logs.amazonaws.com"
  source_arn     = "${aws_cloudwatch_log_group.etl.arn}:*"
}

# ── Subscription filter: pipe /ecs/etl-job → Lambda ──────────────────────────
resource "aws_cloudwatch_log_subscription_filter" "nr_forwarder" {
  name            = "nr-log-forwarder"
  log_group_name  = aws_cloudwatch_log_group.etl.name
  filter_pattern  = ""   # empty = forward all log events
  destination_arn = aws_serverlessapplicationrepository_cloudformation_stack.nr_log_ingestion.outputs["NewRelicLogIngestionFunctionArn"]
  depends_on      = [aws_lambda_permission.allow_cloudwatch]
}
```

### 5.5 Terraform: `ecs.tf` changes

Remove APM agent environment variables and the `NEW_RELIC_LICENSE_KEY` secret from the task definition:

```hcl
# Remove these from container_definitions environment block:
# { name = "CORECLR_ENABLE_PROFILING",                    value = "1" }
# { name = "CORECLR_PROFILER",                            value = "{36032161-...}" }
# { name = "CORECLR_PROFILER_PATH",                       value = "..." }
# { name = "CORECLR_NEWRELIC_HOME",                       value = "..." }
# { name = "NEW_RELIC_APP_NAME",                          value = "..." }
# { name = "NEW_RELIC_APPLICATION_LOGGING_ENABLED",       value = "true" }
# { name = "NEW_RELIC_APPLICATION_LOGGING_FORWARDING...", value = "true" }
# { name = "NEW_RELIC_SEND_DATA_ON_EXIT",                 value = "true" }
# { name = "NEW_RELIC_SEND_DATA_ON_EXIT_THRESHOLD_MS",    value = "0" }

# Remove from secrets block:
# { name = "NEW_RELIC_LICENSE_KEY", valueFrom = aws_ssm_parameter.nr_license_key.arn }
```

### 5.6 New Relic Dashboard (after migration)

Logs will appear in New Relic under **Logs** (not APM). NRQL queries change slightly:

| Panel | Old NRQL (APM) | New NRQL (Logs) |
|---|---|---|
| Log volume | `FROM Log WHERE entity.name = 'etl-job'` | `FROM Log WHERE aws.logGroup = '/ecs/etl-job'` |
| WARN/ERROR | `FROM Log WHERE level IN ('WARN','ERROR')` | `FROM Log WHERE aws.logGroup = '/ecs/etl-job' AND message LIKE '%WARN%'` |
| ETL run timeline | `FROM Transaction WHERE appName = 'etl-job'` | `FROM Log WHERE aws.logGroup = '/ecs/etl-job' AND message LIKE '%ETL job%'` |

> APM-style transaction traces are no longer available (no APM agent). All observability comes from log analysis. This is sufficient for the project goals.

---

## 6. Implementation Steps

### Phase 1 — Simplify the Application (no AWS changes)

1. **`Dockerfile`** — Remove the New Relic agent install layer and all `CORECLR_*` / `NEW_RELIC_*` ENV vars.
2. **`src/EtlJob/Program.cs`** — Remove `await Task.Delay(...)` and its comment.
3. **Verify locally:** `docker build . -t etl-job:test && docker run etl-job:test` — confirm logs print and container exits cleanly with code 0.
4. **Push to Docker Hub** via GitHub Actions.

### Phase 2 — Add Lambda Forwarder in Terraform

5. **`terraform/lambda.tf`** — New file with SAR stack, Lambda permission, and subscription filter (see §5.4).
6. **`terraform/ecs.tf`** — Remove APM agent env vars and the NR license key secret reference from the task definition.
7. **`terraform/iam.tf`** — Remove the `ssm:GetParameters` grant for the NR key from the ECS execution role (ECS no longer needs it; Lambda inherits it from the SAR-created role).
8. **`terraform apply`** — Deploy the Lambda and subscription filter.

### Phase 3 — Validate End-to-End

9. Trigger an ECS task run manually: `aws ecs run-task ...`
10. Check CloudWatch log group `/ecs/etl-job` — confirm logs appear.
11. Check New Relic **Logs** → search `aws.logGroup = '/ecs/etl-job'` — confirm log events arrive within ~30 seconds of the container exiting.
12. Verify the ETL container runtime is now ~1–2 seconds (no 40-second delay).

### Phase 4 — Update Dashboard

13. In New Relic Logs UI, create saved views / alerts based on `aws.logGroup = '/ecs/etl-job'`.
14. Update any existing dashboard NRQL to use the Log-based queries from §5.6.

---

## 7. Trade-offs vs APM Agent

| Dimension | APM Agent (old) | Lambda Forwarder (new) |
|---|---|---|
| **Reliability** | Flaky for short-lived containers; harvest cycle mismatches | Reliable — CloudWatch subscription + Lambda retry |
| **Log latency** | Immediate (in-process, when it flushes) | ~5–30 s (CloudWatch buffer + Lambda cold start) |
| **Image size** | ~700 MB (agent install layer) | ~220 MB (clean runtime image) |
| **Container run time** | +40 s idle delay | +0 s; job exits immediately |
| **APM traces** | Yes (transaction traces, method-level) | No — logs only |
| **Cost** | ~$0/mo (ECS + CloudWatch, no Lambda) | ~$0/mo (Lambda free tier covers thousands of runs/day) |
| **Complexity** | Agent in image + env vars | Lambda + subscription filter in Terraform |
| **Maintenance** | NR agent version pinning | SAR stack auto-updates (or pin semantic version) |

> For this project's goals (log visibility, ETL run tracking, dashboard), the Lambda Forwarder is the correct tool. APM traces are only valuable for long-running services where method-level profiling reveals bottlenecks.

---

## 8. Cost Impact

| Resource | Old cost | New cost |
|---|---|---|
| New Relic .NET agent (image layer) | ~40 MB storage | $0 |
| Lambda invocations (1/day, tiny payload) | — | ~$0 (well within free tier) |
| Lambda duration (< 1 s per run) | — | ~$0 |
| ECS run time (was +40 s for delay) | Higher | Shorter → saves ~$0.002/run |
| **Net change** | | **~$0 difference; leaner image** |

---

## 9. Files Modified Summary

| File | Change |
|---|---|
| `Dockerfile` | Remove NR agent install + all NR ENV vars |
| `src/EtlJob/Program.cs` | Remove `Task.Delay(40s)` and its comment block |
| `terraform/lambda.tf` | **New** — SAR Lambda, IAM permission, subscription filter |
| `terraform/ecs.tf` | Remove APM agent env vars + NR license key secret from task def |
| `terraform/iam.tf` | Remove `ssm:GetParameters` for NR key from ECS execution role |
| `IMPLEMENTATION.md` | Update §3 (telemetry choice) and §5.2 (short-lived-process section) |

---

### References

- [New Relic log ingestion Lambda (GitHub)](https://github.com/newrelic/aws-log-ingestion)
- [New Relic log ingestion SAR](https://serverlessrepo.aws.amazon.com/applications/arn:aws:serverlessrepo:us-east-1:463657938898:applications~NewRelic-log-ingestion)
- [New Relic Log API](https://docs.newrelic.com/docs/logs/log-api/introduction-log-api/)
- [CloudWatch Logs subscription filters — AWS docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/SubscriptionFilters.html)
- [aws_serverlessapplicationrepository_cloudformation_stack — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/serverlessapplicationrepository_cloudformation_stack)
