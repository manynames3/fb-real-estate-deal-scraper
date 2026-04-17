terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ── ACCOUNT IDENTITY ─────────────────────────────────────────
data "aws_caller_identity" "current" {}

# ── VARIABLES ───────────────────────────────────────────────
variable "scrapecreators_api_key" {
  description = "ScrapeCreators API key"
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Email address to receive deal alerts"
  type        = string
}

variable "fb_group_urls" {
  description = "Comma-separated list of Facebook group URLs"
  type        = string
  default     = "https://www.facebook.com/groups/atlant.realestate.wholesalers,https://www.facebook.com/groups/353876517547400,https://www.facebook.com/groups/georgiaoffmarketproperties,https://www.facebook.com/groups/atlanta.ga.real.estate.investing,https://www.facebook.com/groups/364263283590058"
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  region      = "us-east-1"
  project     = "fb-deal-finder"
}

# ── DYNAMODB TABLE ───────────────────────────────────────────
resource "aws_dynamodb_table" "deal_posts" {
  name         = "fb-deal-posts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "post_id"

  attribute {
    name = "post_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = {
    Project = local.project
  }
}

# ── SNS TOPIC ────────────────────────────────────────────────
resource "aws_sns_topic" "deal_alerts" {
  name = "deal-alerts"

  tags = {
    Project = local.project
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.deal_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── IAM ROLE FOR LAMBDA ──────────────────────────────────────
resource "aws_iam_role" "lambda_role" {
  name = "deal-finder-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = local.project
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_sns" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── LAMBDA LAYER (requests library) ─────────────────────────
resource "aws_lambda_layer_version" "requests" {
  filename            = "${path.module}/requests-layer.zip"
  layer_name          = "requests-layer"
  compatible_runtimes = ["python3.12"]

  lifecycle {
    create_before_destroy = true
  }
}

# ── LAMBDA FUNCTION ──────────────────────────────────────────
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "deal_finder" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "fb-deal-finder"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  memory_size      = 128
  layers           = [aws_lambda_layer_version.requests.arn]

  environment {
    variables = {
      SCRAPECREATORS_API_KEY = var.scrapecreators_api_key
      FB_GROUP_URLS          = var.fb_group_urls
      SNS_TOPIC_ARN          = aws_sns_topic.deal_alerts.arn
      DYNAMODB_TABLE         = aws_dynamodb_table.deal_posts.name
    }
  }

  tags = {
    Project = local.project
  }
}

# ── IAM ROLE FOR EVENTBRIDGE ─────────────────────────────────
resource "aws_iam_role" "eventbridge_role" {
  name = "deal-finder-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = local.project
  }
}

resource "aws_iam_role_policy" "eventbridge_lambda_invoke" {
  name = "eventbridge-lambda-invoke"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "lambda:InvokeFunction"
        Effect   = "Allow"
        Resource = aws_lambda_function.deal_finder.arn
      }
    ]
  })
}

# ── EVENTBRIDGE SCHEDULER ────────────────────────────────────
resource "aws_scheduler_schedule" "deal_finder" {
  name       = "fb-deal-finder-schedule"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  # Every 3 days at 11 PM Eastern Time
  schedule_expression          = "cron(0 23 */3 * ? *)"
  schedule_expression_timezone = "America/New_York"

  target {
    arn      = aws_lambda_function.deal_finder.arn
    role_arn = aws_iam_role.eventbridge_role.arn

    input = jsonencode({})
  }
}

# ── LAMBDA PERMISSION FOR EVENTBRIDGE ───────────────────────
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.deal_finder.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.deal_finder.arn
}

# ── CLOUDWATCH LOG GROUP ─────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.deal_finder.function_name}"
  retention_in_days = 30

  tags = {
    Project = local.project
  }
}

# ── OUTPUTS ──────────────────────────────────────────────────
output "lambda_function_name" {
  value = aws_lambda_function.deal_finder.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.deal_finder.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.deal_posts.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.deal_alerts.arn
}

output "eventbridge_schedule_name" {
  value = aws_scheduler_schedule.deal_finder.name
}
