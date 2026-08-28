resource "aws_cloudwatch_event_rule" "pipeline_schedule" {
  name                = "${local.name_prefix}-pipeline-schedule"
  schedule_expression = var.pipeline_schedule_expression
  state               = var.enable_schedule ? "ENABLED" : "DISABLED"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "pipeline_schedule" {
  rule     = aws_cloudwatch_event_rule.pipeline_schedule.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.eventbridge_scheduler.arn
}
