resource "aws_sqs_queue" "analytics" {
  name                       = "${var.project_name}-analytics-events"
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 20

  tags = { Name = "${var.project_name}-analytics-events" }
}
