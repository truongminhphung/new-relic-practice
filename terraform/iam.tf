# ---- shared assume-role policies ----

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

# ---- task execution role ----
# Used by the ECS agent (not the app) to pull the image and ship logs.

resource "aws_iam_role" "task_exec" {
  name               = "${local.name}-task-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "task_exec_managed" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---- task role ----
# Assumed by the running container. No AWS API calls needed for this ETL,
# so it stays empty — add policies here if the app ever needs AWS access.

resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.tags
}

# ---- scheduler role ----
# EventBridge Scheduler needs ecs:RunTask + iam:PassRole to launch the task.

resource "aws_iam_role" "scheduler" {
  name               = "${local.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "scheduler_ecs" {
  statement {
    actions   = ["ecs:RunTask"]
    resources = [aws_ecs_task_definition.etl.arn]
  }
  statement {
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.task_exec.arn,
      aws_iam_role.task.arn,
    ]
  }
}

resource "aws_iam_role_policy" "scheduler_ecs" {
  name   = "${local.name}-scheduler-ecs"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_ecs.json
}
