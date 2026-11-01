# CloudWatch Logs + 2 alarm + SNS email — cùng tên và thông số với 06-AWS bài 10.

# /taskhub/dev/app — compose.aws.yaml (log driver awslogs) ghi vào đây.
# Retention mặc định là "Never expire" = bẫy chi phí → luôn đặt.
resource "aws_cloudwatch_log_group" "app" {
  name              = "${local.path_prefix}/app"
  retention_in_days = 7
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

# Email phải được XÁC NHẬN bằng link AWS gửi tới. Xóa topic (terraform destroy) thì SNS
# xóa luôn mọi subscription của topic, kể cả subscription chưa xác nhận.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  alarm_description   = "taskhub-app CPU > 80% trong 10 phut"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = module.app_server.instance_id }
  statistic           = "Average"
  period              = 300 # basic monitoring: 1 điểm / 5 phút
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${local.name_prefix}-status-check"
  alarm_description   = "taskhub-app status check failed"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = module.app_server.instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
